#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"
REPORT_DIR="$ROOT_DIR/artifacts/offboarding"
OPS_DB="${OPS_DB:-$ROOT_DIR/.codex/mcp/homelab_ops.sqlite}"
INVENTORY="${INVENTORY:-inventory/hosts}"

username=""
ticket_ref=""
reason=""
effective_at=""
approved_by=""
confirm_username=""
mode="plan"
output_dir=""
vars_file=""
asset_file=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/offboard-employee.sh \
    --username USERNAME \
    --ticket-ref TICKET_REF \
    --reason REASON \
    [--effective-at TIMESTAMP] \
    [--output-dir DIR]

Plan mode is the default. It records intended controls and assigned assets
without changing AD, Keycloak, Nextcloud, or asset state.

To execute the access containment workflow:
  ./scripts/offboard-employee.sh \
    --username USERNAME \
    --ticket-ref TICKET_REF \
    --reason REASON \
    --approved-by APPROVER \
    --execute \
    --confirm-username USERNAME

Execution disables the AD account, removes only managed department groups,
revokes Keycloak sessions, disables a matching Nextcloud user when present,
and marks assigned endpoint assets as recovery_pending. It never deletes an
identity, mailbox, home directory, or asset record.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 2
}

cleanup() {
  [[ -n "$vars_file" ]] && rm -f "$vars_file"
  [[ -n "$asset_file" ]] && rm -f "$asset_file"
}
trap cleanup EXIT INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username|--ticket-ref|--reason|--effective-at|--approved-by|--confirm-username|--output-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --username) username="$2" ;;
        --ticket-ref) ticket_ref="$2" ;;
        --reason) reason="$2" ;;
        --effective-at) effective_at="$2" ;;
        --approved-by) approved_by="$2" ;;
        --confirm-username) confirm_username="$2" ;;
        --output-dir) output_dir="$2" ;;
      esac
      shift 2
      ;;
    --execute)
      mode="execute"
      shift
      ;;
    --plan)
      mode="plan"
      shift
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

[[ -n "$username" ]] || die "--username is required"
[[ -n "$ticket_ref" ]] || die "--ticket-ref is required"
[[ -n "$reason" ]] || die "--reason is required"
[[ "$username" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] ||
  die "--username must contain only lowercase letters, digits, dot, underscore, or hyphen"

for value in "$ticket_ref" "$reason" "$effective_at" "$approved_by" "$confirm_username"; do
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] ||
    die "input values must be single-line"
done

case "$username" in
  administrator|guest|krbtgt|sysadmin)
    die "protected account cannot be offboarded: $username"
    ;;
esac

if [[ "$mode" == "execute" ]]; then
  [[ -n "$approved_by" ]] || die "--approved-by is required with --execute"
  [[ "$confirm_username" == "$username" ]] ||
    die "--confirm-username must exactly match --username"
  [[ -f "$ANSIBLE_DIR/$INVENTORY" ]] ||
    die "inventory not found: $ANSIBLE_DIR/$INVENTORY"
  command -v ansible-playbook >/dev/null 2>&1 || die "ansible-playbook is required"
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required"
[[ -n "$effective_at" ]] || effective_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
[[ -n "$output_dir" ]] && REPORT_DIR="$output_dir"
mkdir -p "$REPORT_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
report_path="$REPORT_DIR/$timestamp-$username-$mode.md"
apply_log="$REPORT_DIR/$timestamp-$username-apply.log"
verify_log="$REPORT_DIR/$timestamp-$username-verify.log"
relative_report="${report_path#$ROOT_DIR/}"
relative_apply_log="${apply_log#$ROOT_DIR/}"
relative_verify_log="${verify_log#$ROOT_DIR/}"

asset_file="$(mktemp)"
OFFBOARD_DB="$OPS_DB" OFFBOARD_USER="$username" python3 >"$asset_file" <<'PY_ASSETS'
import json
import os
import pathlib
import sqlite3
import sys

db_path = pathlib.Path(os.environ["OFFBOARD_DB"])
assets = []
if db_path.exists():
    with sqlite3.connect(db_path) as conn:
        has_assets = conn.execute(
            "select 1 from sqlite_master where type='table' and name='assets'"
        ).fetchone()
        if has_assets:
            rows = conn.execute(
                """
                select name, status, coalesce(owner, ''), metadata_json
                from assets
                where owner = ?
                order by name
                """,
                (os.environ["OFFBOARD_USER"],),
            ).fetchall()
            for name, status, owner, metadata_raw in rows:
                metadata = json.loads(metadata_raw or "{}")
                assets.append(
                    {
                        "name": name,
                        "status": status,
                        "owner": owner,
                        "asset_tag": metadata.get("asset_tag"),
                    }
                )

json.dump(assets, sys.stdout)
PY_ASSETS
asset_query_rc=$?
[[ $asset_query_rc -eq 0 ]] || die "could not read assigned assets"
asset_count="$(
  python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' \
    "$asset_file"
)"

record_outcome() {
  local operation_type="$1"
  local record_status="$2"
  local record_summary="$3"
  local apply_rc="$4"
  local verify_rc="$5"

  OFFBOARD_DB="$OPS_DB" OFFBOARD_USER="$username" OFFBOARD_MODE="$mode" \
  OFFBOARD_OPERATION_TYPE="$operation_type" OFFBOARD_STATUS="$record_status" \
  OFFBOARD_SUMMARY="$record_summary" OFFBOARD_TICKET="$ticket_ref" \
  OFFBOARD_REASON="$reason" OFFBOARD_EFFECTIVE_AT="$effective_at" \
  OFFBOARD_APPROVED_BY="$approved_by" OFFBOARD_REPORT="$relative_report" \
  OFFBOARD_APPLY_RC="$apply_rc" OFFBOARD_VERIFY_RC="$verify_rc" \
  OFFBOARD_ASSET_FILE="$asset_file" python3 <<'PY_DB'
import datetime
import json
import os
import pathlib
import sqlite3

db_path = pathlib.Path(os.environ["OFFBOARD_DB"])
db_path.parent.mkdir(parents=True, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
username = os.environ["OFFBOARD_USER"]
mode = os.environ["OFFBOARD_MODE"]

asset_file = pathlib.Path(os.environ["OFFBOARD_ASSET_FILE"])
assets = json.loads(asset_file.read_text())
for asset in assets:
    asset["previous_status"] = asset.pop("status")

details = {
    "mode": mode,
    "ticket_ref": os.environ["OFFBOARD_TICKET"],
    "reason": os.environ["OFFBOARD_REASON"],
    "effective_at": os.environ["OFFBOARD_EFFECTIVE_AT"],
    "approved_by": os.environ["OFFBOARD_APPROVED_BY"] or None,
    "report_path": os.environ["OFFBOARD_REPORT"],
    "apply_return_code": int(os.environ["OFFBOARD_APPLY_RC"]),
    "verify_return_code": int(os.environ["OFFBOARD_VERIFY_RC"]),
    "managed_groups": ["HR_Staff", "Finance_Staff", "IT_Admins", "Security_Team"],
    "assigned_assets": assets,
    "destructive_actions": [],
}

with sqlite3.connect(db_path) as conn:
    conn.execute(
        """create table if not exists assets (
          id integer primary key autoincrement,
          name text not null unique,
          kind text not null,
          status text not null default 'unknown',
          owner text,
          metadata_json text not null default '{}',
          updated_at text not null
        )"""
    )
    conn.execute(
        """create table if not exists operations (
          id integer primary key autoincrement, created_at text not null,
          operation_type text not null, target text not null, status text not null,
          summary text not null, details_json text not null default '{}')"""
    )

    if mode == "execute":
        for asset in assets:
            row = conn.execute(
                "select metadata_json from assets where name = ?", (asset["name"],)
            ).fetchone()
            if row is None:
                continue
            metadata = json.loads(row[0] or "{}")
            metadata["offboarding"] = {
                "ticket_ref": os.environ["OFFBOARD_TICKET"],
                "effective_at": os.environ["OFFBOARD_EFFECTIVE_AT"],
                "previous_status": asset["previous_status"],
                "recovery_status": "pending",
            }
            conn.execute(
                """
                update assets
                set status = 'recovery_pending', metadata_json = ?, updated_at = ?
                where name = ?
                """,
                (json.dumps(metadata, sort_keys=True), now, asset["name"]),
            )

    conn.execute(
        """
        insert into operations(
          created_at, operation_type, target, status, summary, details_json
        ) values (?, ?, ?, ?, ?, ?)
        """,
        (
            now,
            os.environ["OFFBOARD_OPERATION_TYPE"],
            username,
            os.environ["OFFBOARD_STATUS"],
            os.environ["OFFBOARD_SUMMARY"],
            json.dumps(details, sort_keys=True),
        ),
    )

print(len(assets) if mode == "execute" else 0)
PY_DB
}

write_report() {
  local report_status="$1"
  local report_summary="$2"
  local apply_rc="$3"
  local verify_rc="$4"
  local db_result="$5"
  local asset_update_count="$6"

  {
    cat <<EOF_REPORT
# Employee Offboarding Report

## Request

- Mode: \`$mode\`
- Username: \`$username\`
- Ticket: \`$ticket_ref\`
- Reason: $reason
- Effective at: \`$effective_at\`
- Approved by: ${approved_by:-not provided in plan mode}
- Started: \`$started_at\`

## Result

- Status: \`$report_status\`
- Summary: $report_summary
- Apply return code: \`$apply_rc\`
- Verification return code: \`$verify_rc\`
- SQLite: $db_result
- Asset records moved to \`recovery_pending\`: \`$asset_update_count\`

## Access Controls

| Control | Plan |
|---|---|
| AD identity | Disable; never delete |
| Managed groups | Remove HR, Finance, IT, and Security access groups |
| Keycloak | Revoke all sessions for the exact cached username |
| Nextcloud | Disable the exact local user when present |
| Mail | Block new authentication through the disabled AD source account |
| Data | Preserve mailbox, files, identity, and audit records |

## Assigned Assets

EOF_REPORT

    if [[ $asset_count -eq 0 ]]; then
      printf 'No assets are currently assigned to `%s` in the operations DB.\n\n' "$username"
    else
      printf '| Asset | Current status | Owner | Asset tag |\n'
      printf '|---|---|---|---|\n'
      python3 - "$asset_file" <<'PY_REPORT'
import json
import pathlib
import sys

for asset in json.loads(pathlib.Path(sys.argv[1]).read_text()):
    values = {
        key: str(value).replace("|", r"\|")
        for key, value in asset.items()
        if value is not None
    }
    print(
        f"| `{values['name']}` | `{values['status']}` | "
        f"`{values['owner']}` | {values.get('asset_tag', 'not recorded')} |"
    )
PY_REPORT
      printf '\n'
    fi

    cat <<EOF_REPORT
## Evidence

- Apply log: $([[ "$mode" == "execute" ]] && printf '\`%s\`' "$relative_apply_log" || printf 'not run in plan mode')
- Verification log: $([[ "$mode" == "execute" ]] && printf '\`%s\`' "$relative_verify_log" || printf 'not run in plan mode')
- Operations DB: \`.codex/mcp/homelab_ops.sqlite\` or the runtime \`OPS_DB\` override

## Recovery

This workflow is intentionally reversible:

1. Confirm the original request was incorrect or employment was restored.
2. Re-enable the AD account with \`samba-tool user enable $username\`.
3. Re-add only approved department groups from the ticket.
4. Re-enable the matching Nextcloud user when it exists.
5. Restore each asset's prior state from its \`offboarding.previous_status\` metadata.
6. Record the recovery as a separate approved operation.

No account, mailbox, home directory, file, or asset record was deleted by this workflow.
EOF_REPORT
  } > "$report_path"
}

if [[ "$mode" == "plan" ]]; then
  status="planned"
  summary="offboarding controls and assigned asset recovery were planned; no service state changed"
  db_output="$(record_outcome employee_offboarding_plan "$status" "$summary" 125 125)"
  db_rc=$?
  if [[ $db_rc -eq 0 ]]; then
    db_result="recorded"
  else
    db_result="failed (exit $db_rc)"
  fi
  write_report "$status" "$summary" 125 125 "$db_result" 0
  echo "Offboarding mode: plan"
  echo "Status: $status"
  echo "Assigned assets: $asset_count"
  echo "Report: $report_path"
  [[ $db_rc -eq 0 ]]
  exit
fi

vars_file="$(mktemp)"
chmod 600 "$vars_file"
python3 - "$vars_file" "$username" "$confirm_username" "$ticket_ref" "$approved_by" <<'PY_VARS'
import json
import pathlib
import sys

output, username, confirmation, ticket_ref, approved_by = sys.argv[1:]
payload = {
    "offboarding_authorized": True,
    "offboard_user_name": username,
    "offboard_confirm_user": confirmation,
    "offboarding_ticket_ref": ticket_ref,
    "offboarding_approved_by": approved_by,
}
pathlib.Path(output).write_text(json.dumps(payload))
PY_VARS

vault_args=()
[[ -f "$ANSIBLE_DIR/.vault_pass" ]] && vault_args=(--vault-password-file .vault_pass)

run_logged() {
  local log_path="$1"
  shift
  "$@" 2>&1 | tee "$log_path"
  return "${PIPESTATUS[0]}"
}

cd "$ANSIBLE_DIR"
run_logged "$apply_log" ansible-playbook -i "$INVENTORY" \
  playbooks/employee-offboarding.yml -e "@$vars_file" "${vault_args[@]}"
apply_rc=$?

if [[ $apply_rc -eq 0 ]]; then
  run_logged "$verify_log" ansible-playbook -i "$INVENTORY" \
    playbooks/employee-offboarding-verify.yml -e "@$vars_file" "${vault_args[@]}"
  verify_rc=$?
else
  verify_rc=125
  printf 'Skipped because offboarding apply failed.\n' > "$verify_log"
fi

if [[ $apply_rc -ne 0 ]]; then
  status="partial"
  summary="offboarding access containment did not complete; assigned assets still require recovery"
elif [[ $verify_rc -ne 0 ]]; then
  status="partial"
  summary="access containment applied but verification failed"
else
  status="success"
  summary="access containment verified and assigned assets marked for recovery"
fi

db_output="$(record_outcome employee_offboarding "$status" "$summary" "$apply_rc" "$verify_rc")"
db_rc=$?
if [[ $db_rc -eq 0 ]]; then
  db_result="recorded"
  asset_update_count="${db_output:-0}"
else
  db_result="failed (exit $db_rc)"
  asset_update_count=0
  if [[ "$status" == "success" ]]; then
    status="partial"
    summary="access containment verified but SQLite recording failed"
  fi
fi

write_report "$status" "$summary" "$apply_rc" "$verify_rc" \
  "$db_result" "$asset_update_count"

echo "Offboarding mode: execute"
echo "Status: $status"
echo "Assigned assets: $asset_count"
echo "Assets pending recovery: $asset_update_count"
echo "Report: $report_path"
[[ "$status" == "success" && $db_rc -eq 0 ]]
