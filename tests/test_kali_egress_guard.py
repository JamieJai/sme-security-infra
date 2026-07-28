from __future__ import annotations

import os
import subprocess
import sys
import unittest
import urllib.parse
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import kali_egress_guard as guard


class KaliEgressGuardTests(unittest.TestCase):
    def test_module_imports_from_repository_root(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                "-c",
                "from scripts.kali_egress_guard import VMID; print(VMID)",
            ],
            cwd=ROOT,
            check=True,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.stdout.strip(), "111")

    def test_ruleset_has_fixed_scope_and_default_drop(self) -> None:
        ruleset = guard.render_ruleset()

        self.assertIn("table inet kali_egress_guard", ruleset)
        self.assertIn("chain output", ruleset)
        self.assertIn("policy drop", ruleset)
        self.assertIn("ip daddr 192.168.0.77", ruleset)
        self.assertIn(
            "tcp dport { 22, 445, 3389, 5985, 5986 } counter accept", ruleset
        )
        self.assertIn("udp sport 68 udp dport 67 counter accept", ruleset)
        self.assertNotIn("192.168.0.0/24", ruleset)

    def test_qga_command_uses_repeated_form_fields(self) -> None:
        body = guard.command_form(["/bin/sh", "-c", "id"])
        self.assertEqual(
            urllib.parse.parse_qs(body.decode()),
            {"command": ["/bin/sh", "-c", "id"]},
        )

    def test_verify_command_pins_live_config_hash(self) -> None:
        ruleset = guard.render_ruleset()
        command = guard.verify_command(ruleset)
        expected = __import__("hashlib").sha256(ruleset.encode()).hexdigest()

        self.assertEqual(command[:2], ["/bin/sh", "-c"])
        self.assertIn(expected, command[2])
        self.assertIn("systemctl is-enabled nftables", command[2])
        self.assertIn("192.168.0.77", command[2])

    def test_execution_ack_is_exact(self) -> None:
        with mock.patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(SystemExit):
                guard.require_execution_ack()
        with mock.patch.dict(
            os.environ, {guard.ACK_ENV: guard.EXECUTION_ACK}, clear=True
        ):
            guard.require_execution_ack()

    def test_qga_exec_polls_and_returns_output(self) -> None:
        responses = [
            {"data": {"pid": 42}},
            {"data": {"exited": 0}},
            {"data": {"exited": 1, "exitcode": 0, "out-data": "ok\n"}},
        ]
        request = mock.Mock(side_effect=responses)

        with mock.patch.object(guard.time, "sleep"):
            output = guard.qga_exec(
                "https://proxmox/api2/json",
                "token-id",
                "token-secret",
                ["/usr/bin/id"],
                request=request,
            )

        self.assertEqual(output, "ok\n")
        self.assertEqual(request.call_count, 3)

    def test_qga_exec_rejects_nonzero_exit(self) -> None:
        request = mock.Mock(
            side_effect=[
                {"data": {"pid": 43}},
                {
                    "data": {
                        "exited": 1,
                        "exitcode": 2,
                        "err-data": "failed",
                    }
                },
            ]
        )

        with self.assertRaisesRegex(RuntimeError, "failed"):
            guard.qga_exec(
                "https://proxmox/api2/json",
                "token-id",
                "token-secret",
                ["/usr/bin/false"],
                request=request,
            )


if __name__ == "__main__":
    unittest.main()
