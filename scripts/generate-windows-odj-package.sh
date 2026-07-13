#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT_DIR/endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1"
OUTPUT_DIR="$ROOT_DIR/artifacts/endpoint-odj"
OPS_DB="$ROOT_DIR/.codex/mcp/homelab_ops.sqlite"
DOMAIN_NAME="${DOMAIN_NAME:-toss.lan}"
DNS_SERVERS="${DNS_SERVERS:-192.168.0.21,192.168.0.20}"
WAZUH_MANAGER="${WAZUH_MANAGER:-192.168.0.30}"
WAZUH_AGENT_VERSION="${WAZUH_AGENT_VERSION:-4.10.4-1}"
WAZUH_AGENT_GROUP="${WAZUH_AGENT_GROUP:-windows}"
WAZUH_MSI_FILE=""
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
    [--wazuh-manager IP_OR_HOST] \
    [--wazuh-agent-version VERSION] \
    [--wazuh-agent-group GROUP] \
    [--wazuh-msi-file PATH] \
    [--output-dir DIR]

Packages a pre-generated Offline Domain Join blob with the Windows apply
script. The apply script installs and enrolls the Wazuh agent before applying
ODJ. The blob is sensitive and must be distributed only through a protected
per-employee or per-device channel.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --employee-id|--computer-name|--blob-file|--wazuh-manager|--wazuh-agent-version|--wazuh-agent-group|--wazuh-msi-file|--output-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --employee-id) EMPLOYEE_ID="$2" ;;
        --computer-name) COMPUTER_NAME="$2" ;;
        --blob-file) BLOB_FILE="$2" ;;
        --wazuh-manager) WAZUH_MANAGER="$2" ;;
        --wazuh-agent-version) WAZUH_AGENT_VERSION="$2" ;;
        --wazuh-agent-group) WAZUH_AGENT_GROUP="$2" ;;
        --wazuh-msi-file) WAZUH_MSI_FILE="$2" ;;
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
if [[ -n "$WAZUH_MSI_FILE" ]]; then
  [[ -f "$WAZUH_MSI_FILE" ]] || die "Wazuh MSI file not found: $WAZUH_MSI_FILE"
fi
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

wazuh_msi_arg=""
wazuh_msi_summary="download from packages.wazuh.com"
wazuh_msi_included="false"
if [[ -n "$WAZUH_MSI_FILE" ]]; then
  wazuh_msi_name="$(basename "$WAZUH_MSI_FILE")"
  cp "$WAZUH_MSI_FILE" "$package_dir/$wazuh_msi_name"
  chmod 600 "$package_dir/$wazuh_msi_name"
  wazuh_msi_arg=" -WazuhMsiPath \"%~dp0$wazuh_msi_name\""
  wazuh_msi_summary="included: $wazuh_msi_name"
  wazuh_msi_included="true"
fi

cat > "$package_dir/run-as-admin.cmd" <<EOF_CMD
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Apply-OfflineDomainJoin.ps1" -EmployeeId "$EMPLOYEE_ID" -ComputerName "$COMPUTER_NAME" -DomainName "$DOMAIN_NAME" -BlobPath "%~dp0odj.blob" -DnsServers "$DNS_SERVERS" -WazuhManager "$WAZUH_MANAGER" -WazuhAgentVersion "$WAZUH_AGENT_VERSION" -WazuhAgentGroup "$WAZUH_AGENT_GROUP"$wazuh_msi_arg
EOF_CMD

cat > "$readme_path" <<EOF_README
Windows Offline Domain Join Package

Employee ID: $EMPLOYEE_ID
Computer Name: $COMPUTER_NAME
Domain: $DOMAIN_NAME
DNS Servers: $DNS_SERVERS
Wazuh Manager: $WAZUH_MANAGER
Wazuh Agent Version: $WAZUH_AGENT_VERSION
Wazuh Agent Group: $WAZUH_AGENT_GROUP
Wazuh MSI Source: $wazuh_msi_summary

Instructions:
1. Log in to Windows with a local administrator account.
2. Right-click run-as-admin.cmd and select Run as administrator.
3. The script installs and enrolls the Wazuh agent, applies the ODJ blob, and restarts the PC.
4. After restart, connect to the corporate network and log in with the AD account.

Security:
- odj.blob is device-specific and sensitive. Do not forward it to another user or PC.
- This package does not contain a reusable domain password.
- If this package is sent to the wrong person or device, contact IT so the AD computer object can be disabled or deleted.
EOF_README
chmod 600 "$readme_path" "$package_dir/run-as-admin.cmd"

relative_package="${package_dir#$ROOT_DIR/}"
ODJ_DB="$OPS_DB" ODJ_TARGET="$COMPUTER_NAME" ODJ_EMPLOYEE="$EMPLOYEE_ID" ODJ_PACKAGE="$relative_package" \
ODJ_WAZUH_MANAGER="$WAZUH_MANAGER" ODJ_WAZUH_AGENT_VERSION="$WAZUH_AGENT_VERSION" \
ODJ_WAZUH_AGENT_GROUP="$WAZUH_AGENT_GROUP" ODJ_WAZUH_MSI_INCLUDED="$wazuh_msi_included" python3 <<'PY_DB'
import datetime, json, os, pathlib, sqlite3
db_path = pathlib.Path(os.environ["ODJ_DB"])
db_path.parent.mkdir(parents=True, exist_ok=True)
details = {
    "employee_id": os.environ["ODJ_EMPLOYEE"],
    "package_path": os.environ["ODJ_PACKAGE"],
    "contains_odj_blob": True,
    "wazuh_manager": os.environ["ODJ_WAZUH_MANAGER"],
    "wazuh_agent_version": os.environ["ODJ_WAZUH_AGENT_VERSION"],
    "wazuh_agent_group": os.environ["ODJ_WAZUH_AGENT_GROUP"],
    "wazuh_msi_included": os.environ["ODJ_WAZUH_MSI_INCLUDED"] == "true",
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
