#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="$ROOT_DIR/artifacts/endpoint-assets"
OPS_DB="$ROOT_DIR/.codex/mcp/homelab_ops.sqlite"

employee_id=""
username=""
computer_name=""
department=""
asset_tag=""
serial_number=""
join_method="manual"
package_path=""
status=""
notes=""
output_dir=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/register-endpoint.sh \
    --employee-id EMPLOYEE_ID \
    --username USERNAME \
    --computer-name COMPUTER_NAME \
    [--department HR|Finance|IT|Security] \
    [--asset-tag ASSET_TAG] \
    [--serial-number SERIAL] \
    [--join-method manual|ad-join|odj] \
    [--package-path PATH] \
    [--status STATUS] \
    [--notes TEXT] \
    [--output-dir DIR]

Registers or updates a Windows endpoint asset in .codex/mcp/homelab_ops.sqlite,
writes a Markdown assignment report, and records an endpoint_register operation.

Do not pass passwords, ODJ blob contents, tokens, webhook URLs, or vault values.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --employee-id|--username|--computer-name|--department|--asset-tag|--serial-number|--join-method|--package-path|--status|--notes|--output-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --employee-id) employee_id="$2" ;;
        --username) username="$2" ;;
        --computer-name) computer_name="$2" ;;
        --department) department="$2" ;;
        --asset-tag) asset_tag="$2" ;;
        --serial-number) serial_number="$2" ;;
        --join-method) join_method="$2" ;;
        --package-path) package_path="$2" ;;
        --status) status="$2" ;;
        --notes) notes="$2" ;;
        --output-dir) output_dir="$2" ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$employee_id" ]] || die "--employee-id is required"
[[ -n "$username" ]] || die "--username is required"
[[ -n "$computer_name" ]] || die "--computer-name is required"

[[ "$employee_id" =~ ^[A-Za-z0-9_.-]{1,64}$ ]] || die "--employee-id contains unsupported characters"
[[ "$username" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "--username contains unsupported characters"
[[ "$computer_name" =~ ^[A-Z0-9][A-Z0-9-]{0,14}$ ]] || die "--computer-name must be uppercase, 1-15 chars, letters/digits/hyphen"

if [[ -n "$department" ]]; then
  case "$department" in
    HR|Finance|IT|Security) ;;
    *) die "--department must be one of: HR, Finance, IT, Security" ;;
  esac
fi
case "$join_method" in
  manual|ad-join|odj) ;;
  *) die "--join-method must be one of: manual, ad-join, odj" ;;
esac

for value in "$asset_tag" "$serial_number" "$package_path" "$status" "$notes"; do
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "free-text values must be single-line"
done
[[ "$package_path" != *"odj.blob"* ]] || die "store the package directory, not the raw odj.blob path"

command -v python3 >/dev/null 2>&1 || die "python3 is required"

if [[ -z "$status" ]]; then
  case "$join_method" in
    odj) status="odj_package_issued" ;;
    ad-join) status="ad_join_package_issued" ;;
    manual) status="registered" ;;
  esac
fi

[[ -n "$output_dir" ]] && REPORT_DIR="$output_dir"
mkdir -p "$REPORT_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
safe_computer="$(printf '%s' "$computer_name" | tr '[:upper:]' '[:lower:]')"
report_path="$REPORT_DIR/$timestamp-$safe_computer.md"
relative_report="${report_path#$ROOT_DIR/}"
relative_package=""
if [[ -n "$package_path" ]]; then
  case "$package_path" in
    "$ROOT_DIR"/*) relative_package="${package_path#$ROOT_DIR/}" ;;
    *) relative_package="$package_path" ;;
  esac
fi

REGISTER_DB="$OPS_DB" REGISTER_REPORT="$relative_report" REGISTER_CREATED_AT="$created_at" \
REGISTER_EMPLOYEE_ID="$employee_id" REGISTER_USERNAME="$username" REGISTER_COMPUTER="$computer_name" \
REGISTER_DEPARTMENT="$department" REGISTER_ASSET_TAG="$asset_tag" REGISTER_SERIAL="$serial_number" \
REGISTER_JOIN_METHOD="$join_method" REGISTER_PACKAGE="$relative_package" REGISTER_STATUS="$status" \
REGISTER_NOTES="$notes" python3 <<'PY_DB'
import datetime, json, os, pathlib, sqlite3

db_path = pathlib.Path(os.environ["REGISTER_DB"])
db_path.parent.mkdir(parents=True, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
computer = os.environ["REGISTER_COMPUTER"]
username = os.environ["REGISTER_USERNAME"]
status = os.environ["REGISTER_STATUS"]
metadata = {
    "employee_id": os.environ["REGISTER_EMPLOYEE_ID"],
    "username": username,
    "computer_name": computer,
    "department": os.environ["REGISTER_DEPARTMENT"] or None,
    "asset_tag": os.environ["REGISTER_ASSET_TAG"] or None,
    "serial_number": os.environ["REGISTER_SERIAL"] or None,
    "join_method": os.environ["REGISTER_JOIN_METHOD"],
    "package_path": os.environ["REGISTER_PACKAGE"] or None,
    "report_path": os.environ["REGISTER_REPORT"],
    "notes": os.environ["REGISTER_NOTES"] or None,
}
metadata = {key: value for key, value in metadata.items() if value is not None}
details = dict(metadata)
details["asset_kind"] = "endpoint"
with sqlite3.connect(db_path) as conn:
    conn.execute("""create table if not exists assets (
      id integer primary key autoincrement,
      name text not null unique,
      kind text not null,
      status text not null default 'unknown',
      owner text,
      metadata_json text not null default '{}',
      updated_at text not null
    )""")
    conn.execute("""create table if not exists operations (
      id integer primary key autoincrement, created_at text not null,
      operation_type text not null, target text not null, status text not null,
      summary text not null, details_json text not null default '{}')""")
    conn.execute(
        """
        insert into assets(name, kind, status, owner, metadata_json, updated_at)
        values (?, ?, ?, ?, ?, ?)
        on conflict(name) do update set
          kind=excluded.kind,
          status=excluded.status,
          owner=excluded.owner,
          metadata_json=excluded.metadata_json,
          updated_at=excluded.updated_at
        """,
        (computer, "endpoint", status, username, json.dumps(metadata, sort_keys=True), now),
    )
    conn.execute(
        "insert into operations(created_at, operation_type, target, status, summary, details_json) values (?, ?, ?, ?, ?, ?)",
        (now, "endpoint_register", computer, "success", f"Endpoint asset registered for {username}", json.dumps(details, sort_keys=True)),
    )
PY_DB

cat > "$report_path" <<EOF_REPORT
# Endpoint Asset Registration Report

## Summary

- Status: \`$status\`
- Created: \`$created_at\`
- Employee ID: \`$employee_id\`
- Username: \`$username\`
- Computer name: \`$computer_name\`
- Department: ${department:-not provided}
- Asset tag: ${asset_tag:-not provided}
- Serial number: ${serial_number:-not provided}
- Join method: \`$join_method\`
- Package path: ${relative_package:-not provided}

## Operational Context

- Asset kind: \`endpoint\`
- Asset DB name: \`$computer_name\`
- Asset owner: \`$username\`
- Operations DB: \`.codex/mcp/homelab_ops.sqlite\`

## Next Steps

- If join method is \`ad-join\`, deliver the no-secret AD Join package through a protected channel.
- If join method is \`odj\`, confirm the package is device-specific and do not share \`odj.blob\` with another PC.
- After the PC joins the domain, run the relevant helpdesk diagnosis only if the user reports a failure.
- Record successful domain login and service access in the onboarding or IT health workflow.

## Helpdesk Follow-up

For domain join issues:

\`./scripts/helpdesk-diagnose.sh --scenario domain-join --username $username --computer-name $computer_name\`

For post-join login issues:

\`./scripts/helpdesk-diagnose.sh --scenario ad-login --username $username --computer-name $computer_name\`

## Evidence Handling

- Do not store passwords, ODJ blob contents, tokens, webhook URLs, or vault values in this report.
- AD computer object disable/delete and package recovery require approval.
EOF_REPORT

cat <<EOF
Endpoint registered: $computer_name
Owner: $username
Status: $status
Report: $report_path
SQLite: recorded
EOF
