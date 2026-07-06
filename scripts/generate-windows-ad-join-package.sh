#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT_DIR/endpoint/windows/ad-join-self-service/Join-HomelabDomain.ps1"
OUTPUT_DIR="$ROOT_DIR/artifacts/endpoint-join"
DOMAIN_NAME="${DOMAIN_NAME:-toss.lan}"
DOMAIN_NETBIOS_NAME="${DOMAIN_NETBIOS_NAME:-TOSS}"
DNS_SERVERS="${DNS_SERVERS:-192.168.0.10,192.168.0.11}"
EMPLOYEE_ID=""
COMPUTER_NAME=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/generate-windows-ad-join-package.sh \
    --employee-id EMPLOYEE_ID \
    [--computer-name COMPUTER_NAME] \
    [--output-dir DIR]

Generates a no-secret Windows AD join package for the employee onboarding portal.
The generated PowerShell script prompts for AD credentials at execution time.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --employee-id|--computer-name|--output-dir)
      [[ $# -ge 2 ]] || { echo "Error: $1 requires a value" >&2; exit 2; }
      case "$1" in
        --employee-id) EMPLOYEE_ID="$2" ;;
        --computer-name) COMPUTER_NAME="$2" ;;
        --output-dir) OUTPUT_DIR="$2" ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$EMPLOYEE_ID" ]] || { echo "Error: --employee-id is required" >&2; exit 2; }
[[ -f "$TEMPLATE" ]] || { echo "Error: template not found: $TEMPLATE" >&2; exit 2; }

safe_employee="$(printf '%s' "$EMPLOYEE_ID" | tr -cd 'A-Za-z0-9_.-' | tr '[:upper:]' '[:lower:]')"
[[ -n "$safe_employee" ]] || { echo "Error: employee id contains no safe characters" >&2; exit 2; }

if [[ -z "$COMPUTER_NAME" ]]; then
  suffix="$(printf '%s' "$safe_employee" | tr -cd 'A-Za-z0-9' | tr '[:lower:]' '[:upper:]')"
  suffix="${suffix: -10}"
  COMPUTER_NAME="PC-$suffix"
fi

package_dir="$OUTPUT_DIR/$safe_employee"
mkdir -p "$package_dir"
script_path="$package_dir/join-$safe_employee.ps1"
readme_path="$package_dir/README.txt"

cp "$TEMPLATE" "$script_path"

cat > "$package_dir/run-as-admin.cmd" <<EOF_CMD
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0join-$safe_employee.ps1" -EmployeeId "$EMPLOYEE_ID" -ComputerName "$COMPUTER_NAME" -DomainName "$DOMAIN_NAME" -DomainNetbiosName "$DOMAIN_NETBIOS_NAME" -DnsServers "$DNS_SERVERS"
EOF_CMD

cat > "$readme_path" <<EOF_README
Windows AD Join Package

Employee ID: $EMPLOYEE_ID
Computer Name: $COMPUTER_NAME
Domain: $DOMAIN_NAME
DNS Servers: $DNS_SERVERS

Instructions:
1. Log in to Windows with a local administrator account.
2. Right-click run-as-admin.cmd and select Run as administrator.
3. Enter your AD credential when prompted.
4. The PC will restart unless the script is modified with -NoRestart.

Security:
- This package contains no domain join password or token.
- Do not upload screenshots or logs containing credentials.
- If DNS resolution fails, set DNS to the AD DNS servers first and rerun.
EOF_README

cat <<EOF
Package: $package_dir
Script: $script_path
Launcher: $package_dir/run-as-admin.cmd
EOF
