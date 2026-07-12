#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT_DIR/endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1"
OUTPUT_DIR="$ROOT_DIR/artifacts/endpoint-odj"
OPS_DB="$ROOT_DIR/.codex/mcp/homelab_ops.sqlite"
DOMAIN_NAME="${DOMAIN_NAME:-toss.lan}"
DNS_SERVERS="${DNS_SERVERS:-192.168.0.21,192.168.0.20}"
EMPLOYEE_ID=""
COMPUTER_NAME=""
BLOB_FILE=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/generate-windows-odj-package.sh \
    --employee-id EMPLOYEE_ID \
    --computer-name COMPUTER_NAME \
    --blob-file PATH \
    [--output-dir DIR]

Packages a pre-generated Offline Domain Join blob with the Windows apply
script. The blob is sensitive and must be distributed only through a protected
per-employee or per-device channel.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --employee-id|--computer-name|--blob-file|--output-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --employee-id) EMPLOYEE_ID="$2" ;;
        --computer-name) COMPUTER_NAME="$2" ;;
        --blob-file) BLOB_FILE="$2" ;;
        --output-dir) OUTPUT_DIR="$2" ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$EMPLOYEE_ID" ]] || die "--employee-id is required"
[[ -n "$COMPUTER_NAME" ]] || die "--computer-name is required"
[[ -n "$BLOB_FILE" ]] || die "--blob-file is required"
[[ -f "$TEMPLATE" ]] || die "template not found: $TEMPLATE"
[[ -f "$BLOB_FILE" ]] || die "blob file not found: $BLOB_FILE"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

safe_employee="$(printf '%s' "$EMPLOYEE_ID" | tr -cd 'A-Za-z0-9_.-' | tr '[:upper:]' '[:lower:]')"
safe_computer="$(printf '%s' "$COMPUTER_NAME" | tr -cd 'A-Za-z0-9-' | tr '[:lower:]' '[:upper:]')"
[[ -n "$safe_employee" ]] || die "employee id contains no safe characters"
[[ "$safe_computer" == "$COMPUTER_NAME" ]] || die "--computer-name must contain only uppercase letters, digits, and hyphen"
[[ "${#COMPUTER_NAME}" -le 15 ]] || die "--computer-name must be 15 characters or fewer"

package_dir="$OUTPUT_DIR/$safe_employee/$COMPUTER_NAME"
mkdir -p "$package_dir"
chmod 700 "$OUTPUT_DIR" "$OUTPUT_DIR/$safe_employee" "$package_dir" 2>/dev/null || true

script_path="$package_dir/Apply-OfflineDomainJoin.ps1"
blob_path="$package_dir/odj.blob"
readme_path="$package_dir/README.txt"

cp "$TEMPLATE" "$script_path"
cp "$BLOB_FILE" "$blob_path"
chmod 600 "$script_path" "$blob_path"

cat > "$package_dir/run-as-admin.cmd" <<EOF_CMD
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-OfflineDomainJoin.ps1" -EmployeeId "$EMPLOYEE_ID" -ComputerName "$COMPUTER_NAME" -DomainName "$DOMAIN_NAME" -BlobPath "%~dp0odj.blob" -DnsServers "$DNS_SERVERS"
EOF_CMD

cat > "$readme_path" <<EOF_README
Windows Offline Domain Join Package

Employee ID: $EMPLOYEE_ID
Computer Name: $COMPUTER_NAME
Domain: $DOMAIN_NAME
DNS Servers: $DNS_SERVERS

Instructions:
1. Log in to Windows with a local administrator account.
2. Right-click run-as-admin.cmd and select Run as administrator.
3. The PC will apply the ODJ blob and restart.
4. After restart, connect to the corporate network and log in with the AD account.

Security:
- odj.blob is device-specific and sensitive. Do not forward it to another user or PC.
- This package does not contain a reusable domain password.
- If this package is sent to the wrong person or device, contact IT so the AD computer object can be disabled or deleted.
EOF_README
chmod 600 "$readme_path" "$package_dir/run-as-admin.cmd"

relative_package="${package_dir#$ROOT_DIR/}"
ODJ_DB="$OPS_DB" ODJ_TARGET="$COMPUTER_NAME" ODJ_EMPLOYEE="$EMPLOYEE_ID" ODJ_PACKAGE="$relative_package" python3 <<'PY_DB'
import datetime, json, os, pathlib, sqlite3
db_path = pathlib.Path(os.environ["ODJ_DB"])
db_path.parent.mkdir(parents=True, exist_ok=True)
details = {
    "employee_id": os.environ["ODJ_EMPLOYEE"],
    "package_path": os.environ["ODJ_PACKAGE"],
    "contains_odj_blob": True,
}
with sqlite3.connect(db_path) as conn:
    conn.execute("""create table if not exists operations (
      id integer primary key autoincrement, created_at text not null,
      operation_type text not null, target text not null, status text not null,
      summary text not null, details_json text not null default '{}')""")
    conn.execute(
        "insert into operations(created_at, operation_type, target, status, summary, details_json) values (?, ?, ?, ?, ?, ?)",
        (datetime.datetime.now(datetime.timezone.utc).isoformat(), "endpoint_odj_package",
         os.environ["ODJ_TARGET"], "success", "Windows ODJ package generated",
         json.dumps(details, sort_keys=True)),
    )
PY_DB

cat <<EOF
Package: $package_dir
Script: $script_path
Blob: $blob_path
Launcher: $package_dir/run-as-admin.cmd
SQLite: recorded
EOF
