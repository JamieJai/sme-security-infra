#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"
REPORT_DIR="$ROOT_DIR/artifacts/offboarding-recovery"
OPS_DB="${OPS_DB:-$ROOT_DIR/.codex/mcp/homelab_ops.sqlite}"
INVENTORY="${INVENTORY:-inventory/hosts}"

username=""
ticket_ref=""
reason=""
approved_by=""
confirm_username=""
mode="plan"
output_dir=""
vars_file=""
asset_file=""
recovery_groups=()

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/recover-offboarded-employee.sh \
    --username USERNAME \
    --ticket-ref TICKET_REF \
    --reason REASON \
    --group HR_Staff|Finance_Staff|IT_Admins|Security_Team \
    [--group GROUP] \
    [--output-dir DIR]

Plan mode is the default and changes no identity or asset state.

To execute an approved recovery:
  ./scripts/recover-offboarded-employee.sh \
    --username USERNAME \
    --ticket-ref TICKET_REF \
    --reason REASON \
    --group GROUP \
    --approved-by APPROVER \
    --execute \
    --confirm-username USERNAME

Execution re-enables the AD account, restores only explicitly approved managed
groups, re-enables a matching Nextcloud user, and restores recovery_pending
assets to their recorded previous status. It does not restore old sessions.
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
    --username|--ticket-ref|--reason|--approved-by|--confirm-username|--output-dir|--group)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --username) username="$2" ;;
        --ticket-ref) ticket_ref="$2" ;;
        --reason) reason="$2" ;;
        --approved-by) approved_by="$2" ;;
        --confirm-username) confirm_username="$2" ;;
        --output-dir) output_dir="$2" ;;
        --group) recovery_groups+=("$2") ;;
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
[[ ${#recovery_groups[@]} -gt 0 ]] || die "at least one --group is required"
[[ "$username" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] ||
  die "--username must contain only lowercase letters, digits, dot, underscore, or hyphen"

for value in "$ticket_ref" "$reason" "$approved_by" "$confirm_username" "${recovery_groups[@]}"; do
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] ||
    die "input values must be single-line"
done

case "$username" in
  administrator|guest|krbtgt|sysadmin)
    die "protected account cannot be recovered through this workflow: $username"
    ;;
esac

declare -A seen_groups=()
normalized_groups=()
for group in "${recovery_groups[@]}"; do
  case "$group" in
    HR_Staff|Finance_Staff|IT_Admins|Security_Team) ;;
    *) die "unsupported managed group: $group" ;;
  esac
  if [[ -z "${seen_groups[$group]:-}" ]]; then
    normalized_groups+=("$group")
    seen_groups["$group"]=1
  fi
done
recovery_groups=("${normalized_groups[@]}")

if [[ "$mode" == "execute" ]]; then
  [[ -n "$approved_by" ]] || die "--approved-by is required with --execute"
  [[ "$confirm_username" == "$username" ]] ||
    die "--confirm-username must exactly match --username"
  [[ -f "$ANSIBLE_DIR/$INVENTORY" ]] ||
    die "inventory not found: $ANSIBLE_DIR/$INVENTORY"
  command -v ansible-playbook >/dev/null 2>&1 || die "ansible-playbook is required"
fi

command -v python3 >/dev/null 2>&1 || die "python3 is required"
[[ -n "$output_dir" ]] && REPORT_DIR="$output_dir"
mkdir -p "$REPORT_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
report_path="$REPORT_DIR/$timestamp-$username-$mode.md"
apply_log="$REPORT_DIR/$timestamp-$username-recovery-apply.log"
verify_log="$REPORT_DIR/$timestamp-$username-recovery-verify.log"
relative_report="${report_path#$ROOT_DIR/}"
relative_apply_log="${apply_log#$ROOT_DIR/}"
relative_verify_log="${verify_log#$ROOT_DIR/}"
groups_csv="$(IFS=,; printf '%s' "${recovery_groups[*]}")"

asset_file="$(mktemp)"
RECOVERY_DB="$OPS_DB" RECOVERY_USER="$username" python3 >"$asset_file" <<'PY_ASSETS'
import json
import os
import pathlib
import sqlite3
import sys

db_path = pathlib.Path(os.environ["RECOVERY_DB"])
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
                where owner = ? and status = 'recovery_pending'
                order by name
                """,
                (os.environ["RECOVERY_USER"],),
            ).fetchall()
            for name, status, owner, metadata_raw in rows:
                metadata = json.loads(metadata_raw or "{}")
                offboarding = metadata.get("offboarding") or {}
                assets.append(
                    {
                        "name": name,
                        "status": status,
                        "owner": owner,
                        "asset_tag": metadata.get("asset_tag"),
                        "previous_status": offboarding.get("previous_status"),
                    }
                )

json.dump(assets, sys.stdout)
PY_ASSETS
asset_query_rc=$?
[[ $asset_query_rc -eq 0 ]] || die "could not read recovery-pending assets"
asset_count="$(
  python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))))' \
    "$asset_file"
)"
recoverable_asset_count="$(
  python3 -c \
    'import json,sys; print(sum(bool(a.get("previous_status")) for a in json.load(open(sys.argv[1]))))' \
    "$asset_file"
)"

if [[ "$mode" == "execute" && "$recoverable_asset_count" -ne "$asset_count" ]]; then
  die "one or more recovery-pending assets have no recorded previous status"
fi

record_outcome() {
  local operation_type="$1"
  local record_status="$2"
  local record_summary="$3"
  local apply_rc="$4"
  local verify_rc="$5"

  RECOVERY_DB="$OPS_DB" RECOVERY_USER="$username" RECOVERY_MODE="$mode" \
  RECOVERY_OPERATION_TYPE="$operation_type" RECOVERY_STATUS="$record_status" \
  RECOVERY_SUMMARY="$record_summary" RECOVERY_TICKET="$ticket_ref" \
  RECOVERY_REASON="$reason" RECOVERY_APPROVED_BY="$approved_by" \
  RECOVERY_REPORT="$relative_report" RECOVERY_APPLY_RC="$apply_rc" \
  RECOVERY_VERIFY_RC="$verify_rc" RECOVERY_GROUPS="$groups_csv" \
  RECOVERY_ASSET_FILE="$asset_file" python3 <<'PY_DB'
import datetime
import json
import os
import pathlib
import sqlite3

db_path = pathlib.Path(os.environ["RECOVERY_DB"])
db_path.parent.mkdir(parents=True, exist_ok=True)
now = datetime.datetime.now(datetime.timezone.utc).isoformat()
mode = os.environ["RECOVERY_MODE"]
assets = json.loads(pathlib.Path(os.environ["RECOVERY_ASSET_FILE"]).read_text())
restored_assets = 0

details = {
    "mode": mode,
    "ticket_ref": os.environ["RECOVERY_TICKET"],
    "reason": os.environ["RECOVERY_REASON"],
    "approved_by": os.environ["RECOVERY_APPROVED_BY"] or None,
    "approved_groups": os.environ["RECOVERY_GROUPS"].split(","),
    "report_path": os.environ["RECOVERY_REPORT"],
    "apply_return_code": int(os.environ["RECOVERY_APPLY_RC"]),
    "verify_return_code": int(os.environ["RECOVERY_VERIFY_RC"]),
    "recovery_pending_assets": assets,
    "session_recovery": "new login required",
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

    if (
        mode == "execute"
        and int(os.environ["RECOVERY_APPLY_RC"]) == 0
        and int(os.environ["RECOVERY_VERIFY_RC"]) == 0
    ):
        for asset in assets:
            previous_status = asset.get("previous_status")
            if not previous_status:
                continue
            row = conn.execute(
                "select metadata_json from assets where name = ?", (asset["name"],)
            ).fetchone()
            if row is None:
                continue
            metadata = json.loads(row[0] or "{}")
            metadata["offboarding_recovery"] = {
                "ticket_ref": os.environ["RECOVERY_TICKET"],
                "recovered_at": now,
                "restored_status": previous_status,
            }
            if isinstance(metadata.get("offboarding"), dict):
                metadata["offboarding"]["recovery_status"] = "completed"
            conn.execute(
                """
                update assets
                set status = ?, metadata_json = ?, updated_at = ?
                where name = ?
                """,
                (
                    previous_status,
                    json.dumps(metadata, sort_keys=True),
                    now,
                    asset["name"],
                ),
            )
            restored_assets += 1

    conn.execute(
        """
        insert into operations(
          created_at, operation_type, target, status, summary, details_json
        ) values (?, ?, ?, ?, ?, ?)
        """,
        (
            now,
            os.environ["RECOVERY_OPERATION_TYPE"],
            os.environ["RECOVERY_USER"],
            os.environ["RECOVERY_STATUS"],
            os.environ["RECOVERY_SUMMARY"],
            json.dumps(details, sort_keys=True),
        ),
    )

print(restored_assets)
PY_DB
}

write_report() {
  local report_status="$1"
  local report_summary="$2"
  local apply_rc="$3"
  local verify_rc="$4"
  local db_result="$5"
  local restored_assets="$6"

  {
    cat <<EOF_REPORT
# Employee Offboarding Recovery Report

## Request

- Mode: \`$mode\`
- Username: \`$username\`
- Ticket: \`$ticket_ref\`
- Reason: $reason
- Approved groups: \`$groups_csv\`
- Approved by: ${approved_by:-not provided in plan mode}
- Started: \`$started_at\`

## Result

- Status: \`$report_status\`
- Summary: $report_summary
- Apply return code: \`$apply_rc\`
- Verification return code: \`$verify_rc\`
- SQLite: $db_result
- Asset records restored: \`$restored_assets\`
- Assets with recorded previous status: \`$recoverable_asset_count\`

## Recovery Controls

| Control | Action |
|---|---|
| AD identity | Re-enable only after exact approval |
| Managed groups | Restore only groups named in this request |
| Keycloak | Do not restore old sessions; require a new login |
| Nextcloud | Re-enable exact local user when present |
| Assets | Restore recorded previous status after successful verification |

## Recovery-pending Assets

EOF_REPORT

    if [[ $asset_count -eq 0 ]]; then
      printf 'No recovery-pending assets are assigned to `%s`.\n\n' "$username"
    else
      printf '| Asset | Current status | Previous status | Asset tag |\n'
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
        f"`{values.get('previous_status', 'unknown')}` | "
        f"{values.get('asset_tag', 'not recorded')} |"
    )
PY_REPORT
      printf '\n'
    fi

    cat <<EOF_REPORT
## Evidence

- Apply log: $([[ "$mode" == "execute" ]] && printf '\`%s\`' "$relative_apply_log" || printf 'not run in plan mode')
- Verification log: $([[ "$mode" == "execute" ]] && printf '\`%s\`' "$relative_verify_log" || printf 'not run in plan mode')
- Old Keycloak sessions are intentionally not restored.

This workflow never resets a password, restores an unapproved group, or deletes
an identity, file, mailbox, or asset record.
EOF_REPORT
  } > "$report_path"
}

if [[ "$mode" == "plan" ]]; then
  status="planned"
  summary="identity, approved groups, and asset status recovery were planned; no state changed"
  db_output="$(record_outcome employee_offboarding_recovery_plan "$status" "$summary" 125 125)"
  db_rc=$?
  db_result="recorded"
  [[ $db_rc -eq 0 ]] || db_result="failed (exit $db_rc)"
  write_report "$status" "$summary" 125 125 "$db_result" 0
  echo "Recovery mode: plan"
  echo "Status: $status"
  echo "Recovery-pending assets: $asset_count"
  echo "Report: $report_path"
  [[ $db_rc -eq 0 ]]
  exit
fi

vars_file="$(mktemp)"
chmod 600 "$vars_file"
python3 - "$vars_file" "$username" "$confirm_username" "$ticket_ref" \
  "$approved_by" "${recovery_groups[@]}" <<'PY_VARS'
import json
import pathlib
import sys

output, username, confirmation, ticket_ref, approved_by, *groups = sys.argv[1:]
payload = {
    "offboarding_recovery_authorized": True,
    "offboard_user_name": username,
    "offboard_confirm_user": confirmation,
    "offboarding_ticket_ref": ticket_ref,
    "offboarding_approved_by": approved_by,
    "offboarding_recovery_groups": groups,
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
  playbooks/employee-offboarding-recovery.yml -e "@$vars_file" "${vault_args[@]}"
apply_rc=$?

if [[ $apply_rc -eq 0 ]]; then
  run_logged "$verify_log" ansible-playbook -i "$INVENTORY" \
    playbooks/employee-offboarding-recovery-verify.yml \
    -e "@$vars_file" "${vault_args[@]}"
  verify_rc=$?
else
  verify_rc=125
  printf 'Skipped because recovery apply failed.\n' > "$verify_log"
fi

if [[ $apply_rc -ne 0 ]]; then
  status="partial"
  summary="identity recovery did not complete; assets remain recovery_pending"
elif [[ $verify_rc -ne 0 ]]; then
  status="partial"
  summary="identity recovery applied but verification failed; assets remain recovery_pending"
else
  status="success"
  summary="identity and approved access recovered; eligible asset states restored"
fi

db_output="$(
  record_outcome employee_offboarding_recovery "$status" "$summary" \
    "$apply_rc" "$verify_rc"
)"
db_rc=$?
if [[ $db_rc -eq 0 ]]; then
  db_result="recorded"
  restored_assets="${db_output:-0}"
else
  db_result="failed (exit $db_rc)"
  restored_assets=0
  if [[ "$status" == "success" ]]; then
    status="partial"
    summary="identity recovery verified but SQLite recording failed"
  fi
fi

write_report "$status" "$summary" "$apply_rc" "$verify_rc" \
  "$db_result" "$restored_assets"

echo "Recovery mode: execute"
echo "Status: $status"
echo "Recovery-pending assets: $asset_count"
echo "Assets restored: $restored_assets"
echo "Report: $report_path"
[[ "$status" == "success" && $db_rc -eq 0 ]]
