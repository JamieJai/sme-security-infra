#!/usr/bin/env python3
"""Manage the fixed-scope kali01 nftables egress guard through Proxmox QGA."""

from __future__ import annotations

import argparse
import base64
import hashlib
import os
import sys
import time
import urllib.parse
from pathlib import Path
from typing import Callable

try:
    from proxmox_iso_storage import load_config, proxmox_request
except ModuleNotFoundError:
    from scripts.proxmox_iso_storage import load_config, proxmox_request


NODE = "pve01"
VMID = 111
VM_NAME = "kali01"
VM_ADDRESS = "192.168.0.37"
VM_INTERFACE = "eth0"
TARGET_NAME = "ODJ-VERIFY01"
TARGET_ADDRESS = "192.168.0.77"
TARGET_TCP_PORTS = (22, 445, 3389, 5985, 5986)
DHCP_SERVER = "192.168.0.1"
EXECUTION_ACK = f"{VM_NAME}:{VMID}:{TARGET_ADDRESS}"
ACK_ENV = "KALI_EGRESS_ACK"
DEFAULT_TFVARS = Path("terraform/terraform.tfvars")
NFTABLES_CONFIG = Path("/etc/nftables.conf")
NFTABLES_BACKUP = Path("/etc/nftables.conf.pre-kali-egress-guard")
NFTABLES_ABSENT_MARKER = Path("/etc/nftables.conf.pre-kali-egress-guard.absent")


def render_ruleset() -> str:
    ports = ", ".join(str(port) for port in TARGET_TCP_PORTS)
    return f"""#!/usr/sbin/nft -f
flush ruleset

table inet kali_egress_guard {{
    chain input {{
        type filter hook input priority filter; policy accept;
    }}

    chain forward {{
        type filter hook forward priority filter; policy drop;
        counter drop
    }}

    chain output {{
        type filter hook output priority filter; policy drop;

        oifname "lo" counter accept
        ct state established,related counter accept
        ip daddr {TARGET_ADDRESS} ip protocol icmp counter accept
        ip daddr {TARGET_ADDRESS} tcp dport {{ {ports} }} counter accept
        ip daddr {{ {DHCP_SERVER}, 255.255.255.255 }} udp sport 68 udp dport 67 counter accept
        counter limit rate 5/minute log prefix "kali-egress-drop " drop
    }}
}}
"""


def command_form(command: list[str]) -> bytes:
    if not command or any(not part for part in command):
        raise ValueError("QGA command arguments must be non-empty")
    return urllib.parse.urlencode([("command", part) for part in command]).encode()


def qga_exec(
    api_url: str,
    token_id: str,
    token_secret: str,
    command: list[str],
    *,
    timeout: float = 30,
    request: Callable[..., dict] = proxmox_request,
) -> str:
    body = command_form(command)
    result = request(
        api_url,
        token_id,
        token_secret,
        "POST",
        f"/nodes/{NODE}/qemu/{VMID}/agent/exec",
        body=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    pid = result.get("data", {}).get("pid")
    if not isinstance(pid, int):
        raise RuntimeError(f"QGA exec did not return a PID: {result}")

    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        status = request(
            api_url,
            token_id,
            token_secret,
            "GET",
            f"/nodes/{NODE}/qemu/{VMID}/agent/exec-status?pid={pid}",
        ).get("data", {})
        if status.get("exited") == 1:
            stdout = status.get("out-data", "")
            stderr = status.get("err-data", "")
            if status.get("out-truncated") or status.get("err-truncated"):
                raise RuntimeError("QGA command output was truncated")
            if status.get("exitcode") != 0:
                detail = stderr or stdout or "no command output"
                raise RuntimeError(
                    f"QGA command failed with exit code {status.get('exitcode')}: {detail}"
                )
            return stdout
        time.sleep(0.2)
    raise TimeoutError(f"QGA command timed out after {timeout:g} seconds")


def guest_preflight() -> str:
    return f"""set -eu
test "$(hostname)" = "{VM_NAME}"
ip -4 -o address show dev "{VM_INTERFACE}" | awk '{{print $4}}' | grep -Fx "{VM_ADDRESS}/24" >/dev/null
command -v nft >/dev/null
"""


def check_command(ruleset: str) -> list[str]:
    encoded = base64.b64encode(ruleset.encode()).decode()
    shell = (
        guest_preflight()
        + f"""printf '%s' '{encoded}' | base64 -d | nft --check --file -
printf '%s\\n' 'nftables syntax and guest identity checks passed'
"""
    )
    return ["/bin/sh", "-c", shell]


def apply_command(ruleset: str) -> list[str]:
    encoded = base64.b64encode(ruleset.encode()).decode()
    shell = (
        guest_preflight()
        + f"""tmp="$(mktemp /etc/nftables.conf.kali-egress.XXXXXX)"
trap 'rm -f "$tmp"' EXIT
printf '%s' '{encoded}' | base64 -d > "$tmp"
nft --check --file "$tmp"
if test ! -e "{NFTABLES_BACKUP}" && test ! -e "{NFTABLES_ABSENT_MARKER}"; then
    if test -e "{NFTABLES_CONFIG}"; then
        cp -a "{NFTABLES_CONFIG}" "{NFTABLES_BACKUP}"
    else
        install -m 0600 /dev/null "{NFTABLES_ABSENT_MARKER}"
    fi
fi
install -o root -g root -m 0644 "$tmp" "{NFTABLES_CONFIG}"
nft --file "{NFTABLES_CONFIG}"
systemctl enable --now nftables
systemctl is-enabled nftables
systemctl is-active nftables
nft list table inet kali_egress_guard
"""
    )
    return ["/bin/sh", "-c", shell]


def rollback_command() -> list[str]:
    shell = (
        guest_preflight()
        + f"""if test -e "{NFTABLES_BACKUP}"; then
    install -o root -g root -m 0644 "{NFTABLES_BACKUP}" "{NFTABLES_CONFIG}"
elif test -e "{NFTABLES_ABSENT_MARKER}"; then
    printf '%s\\n' '#!/usr/sbin/nft -f' 'flush ruleset' > "{NFTABLES_CONFIG}"
    chmod 0644 "{NFTABLES_CONFIG}"
else
    printf '%s\\n' 'No recorded pre-guard nftables baseline; refusing rollback.' >&2
    exit 3
fi
systemctl disable --now nftables
nft flush ruleset
systemctl is-enabled nftables 2>/dev/null || true
systemctl is-active nftables 2>/dev/null || true
nft list ruleset
"""
    )
    return ["/bin/sh", "-c", shell]


def status_command() -> list[str]:
    shell = (
        guest_preflight()
        + f"""printf 'service_enabled='
systemctl is-enabled nftables 2>/dev/null || true
printf 'service_active='
systemctl is-active nftables 2>/dev/null || true
printf 'config_sha256='
sha256sum "{NFTABLES_CONFIG}" 2>/dev/null | awk '{{print $1}}' || true
nft -nn list ruleset
"""
    )
    return ["/bin/sh", "-c", shell]


def verify_command(ruleset: str) -> list[str]:
    expected_hash = hashlib.sha256(ruleset.encode()).hexdigest()
    shell = (
        guest_preflight()
        + f"""test "$(systemctl is-enabled nftables)" = enabled
test "$(systemctl is-active nftables)" = active
printf '%s  %s\\n' "{expected_hash}" "{NFTABLES_CONFIG}" | sha256sum --check --status
nft list table inet kali_egress_guard | grep -F "ip daddr {TARGET_ADDRESS}" >/dev/null
printf '%s\\n' 'live kali01 egress guard verification passed'
"""
    )
    return ["/bin/sh", "-c", shell]


def require_execution_ack() -> None:
    if os.environ.get(ACK_ENV) != EXECUTION_ACK:
        raise SystemExit(
            f"Live execution requires {ACK_ENV}={EXECUTION_ACK} and --execute"
        )


def print_plan(action: str, ruleset: str) -> None:
    print(f"Dry run only: {action} kali01 egress guard")
    print(f"Proxmox scope: node={NODE} vmid={VMID} name={VM_NAME}")
    print(f"Allowed target: {TARGET_NAME} / {TARGET_ADDRESS}")
    print(f"Allowed TCP ports: {','.join(map(str, TARGET_TCP_PORTS))}")
    print(f"DHCP renewal: UDP 68 -> {DHCP_SERVER}/255.255.255.255:67")
    print("Inbound policy: accept; forwarding and all other outbound traffic: drop")
    if action == "apply":
        print()
        print(ruleset, end="")
    else:
        print("Rollback restores the recorded pre-guard config and disables nftables.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tfvars", type=Path, default=DEFAULT_TFVARS)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("status", help="Read the live guest nftables state")
    subparsers.add_parser("check", help="Validate the fixed ruleset inside the guest")
    subparsers.add_parser("verify", help="Verify the active persistent guard")
    for name in ("apply", "rollback"):
        action = subparsers.add_parser(name, help=f"{name.title()} the egress guard")
        action.add_argument(
            "--execute",
            action="store_true",
            help="Perform the live change after the acknowledgement guard",
        )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    ruleset = render_ruleset()

    if args.command in {"apply", "rollback"} and not args.execute:
        print_plan(args.command, ruleset)
        return 0

    if args.command in {"apply", "rollback"}:
        require_execution_ack()

    api_url, token_id, token_secret = load_config(args.tfvars)
    commands = {
        "status": status_command(),
        "check": check_command(ruleset),
        "verify": verify_command(ruleset),
        "apply": apply_command(ruleset),
        "rollback": rollback_command(),
    }
    print(qga_exec(api_url, token_id, token_secret, commands[args.command]), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
