#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"
ARTIFACT_DIR="$ROOT_DIR/artifacts/onboarding"
OPS_DB="$ROOT_DIR/.codex/mcp/homelab_ops.sqlite"
INVENTORY="${INVENTORY:-inventory/hosts}"

username=""
given_name=""
surname=""
email=""
department=""
must_change_password="true"
password_file=""
temporary_password=""
vars_file=""
secret_file=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/onboard-employee.sh \
    --username USERNAME \
    --given-name GIVEN_NAME \
    --surname SURNAME \
    --email EMAIL \
    --department HR|Finance|IT|Security \
    [--must-change-password true|false] \
    [--password-file PATH]

The temporary password is read from --password-file, the first line of stdin
when stdin is not a terminal, or a hidden interactive prompt.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 2
}

cleanup() {
  [[ -n "$vars_file" ]] && rm -f "$vars_file"
  [[ -n "$secret_file" ]] && rm -f "$secret_file"
  temporary_password=""
}
trap cleanup EXIT INT TERM

while [[ $# -gt 0 ]]; do
  case "$1" in
    --username|--given-name|--surname|--email|--department|--must-change-password|--password-file)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --username) username="$2" ;;
        --given-name) given_name="$2" ;;
        --surname) surname="$2" ;;
        --email) email="$2" ;;
        --department) department="$2" ;;
        --must-change-password) must_change_password="$2" ;;
        --password-file) password_file="$2" ;;
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

[[ -n "$username" ]] || die "--username is required"
[[ -n "$given_name" ]] || die "--given-name is required"
[[ -n "$surname" ]] || die "--surname is required"
[[ -n "$email" ]] || die "--email is required"
[[ -n "$department" ]] || die "--department is required"
[[ "$username" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] ||
  die "--username must contain only lowercase letters, digits, dot, underscore, or hyphen"
[[ "$given_name" != *$'\n'* && "$surname" != *$'\n'* ]] || die "names must not contain newlines"
[[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]] || die "--email is not valid"
[[ "$must_change_password" == "true" || "$must_change_password" == "false" ]] ||
  die "--must-change-password must be true or false"

case "$department" in
  HR) group="HR_Staff" ;;
  Finance) group="Finance_Staff" ;;
  IT) group="IT_Admins" ;;
  Security) group="Security_Team" ;;
  *) die "--department must be one of: HR, Finance, IT, Security" ;;
esac

[[ -f "$ANSIBLE_DIR/$INVENTORY" ]] || die "inventory not found: $ANSIBLE_DIR/$INVENTORY"
command -v ansible >/dev/null 2>&1 || die "ansible is required"
command -v ansible-playbook >/dev/null 2>&1 || die "ansible-playbook is required"
command -v python3 >/dev/null 2>&1 || die "python3 is required"

if [[ -n "$password_file" ]]; then
  [[ -f "$password_file" ]] || die "password file not found: $password_file"
  IFS= read -r temporary_password < "$password_file" || [[ -n "$temporary_password" ]] ||
    die "could not read password file"
elif [[ ! -t 0 ]]; then
  IFS= read -r temporary_password || [[ -n "$temporary_password" ]] ||
    die "could not read password from stdin"
else
  read -r -s -p "Temporary password: " temporary_password
  echo >&2
fi
[[ -n "$temporary_password" ]] || die "temporary password must not be empty"
[[ "$temporary_password" != *$'\n'* && "$temporary_password" != *$'\r'* ]] ||
  die "temporary password must be a single line"

mkdir -p "$ARTIFACT_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
artifact_base="$ARTIFACT_DIR/$timestamp-$username"
report_path="$artifact_base.md"
onboard_log="$artifact_base-onboard.log"
onboarding_verify_log="$artifact_base-onboarding-verify.log"
service_verify_log="$artifact_base-service-verify.log"

vars_file="$(mktemp)"
secret_file="$(mktemp)"
chmod 600 "$vars_file" "$secret_file"
printf '%s' "$temporary_password" > "$secret_file"
python3 - "$vars_file" "$secret_file" "$username" "$given_name" "$surname" "$email" "$group" "$must_change_password" <<'PY'
import json, pathlib, sys
output, secret_path, username, given_name, surname, email, group, must_change = sys.argv[1:]
payload = {
    "ad_user_name": username,
    "ad_user_given_name": given_name,
    "ad_user_surname": surname,
    "ad_user_email": email,
    "ad_user_groups": [group],
    "ad_user_must_change_password": must_change == "true",
    "ad_user_password": pathlib.Path(secret_path).read_text(),
}
pathlib.Path(output).write_text(json.dumps(payload))
PY
temporary_password=""
rm -f "$secret_file"
secret_file=""

vault_args=()
[[ -f "$ANSIBLE_DIR/.vault_pass" ]] && vault_args=(--vault-password-file .vault_pass)

run_logged() {
  local log_path="$1"
  shift
  "$@" 2>&1 | tee "$log_path"
  return "${PIPESTATUS[0]}"
}

cd "$ANSIBLE_DIR"
run_logged "$onboard_log" ansible-playbook -i "$INVENTORY" playbooks/ad-onboard-user.yml \
  -e "@$vars_file" "${vault_args[@]}"
onboard_rc=$?

if [[ $onboard_rc -eq 0 ]]; then
  run_logged "$onboarding_verify_log" ansible-playbook -i "$INVENTORY" \
    playbooks/employee-onboarding-verify.yml -e "@$vars_file" "${vault_args[@]}"
  onboarding_verify_rc=$?
  run_logged "$service_verify_log" ansible-playbook -i "$INVENTORY" playbooks/verify-all.yml \
    --tags ad,keycloak,nextcloud,mail,wazuh "${vault_args[@]}"
  service_verify_rc=$?
else
  onboarding_verify_rc=125
  service_verify_rc=125
  printf 'Skipped because onboarding failed.\n' | tee \
    "$onboarding_verify_log" "$service_verify_log" >/dev/null
fi

if [[ $onboard_rc -ne 0 ]]; then
  status="failed"
  summary="employee onboarding failed during AD apply"
elif [[ $onboarding_verify_rc -ne 0 || $service_verify_rc -ne 0 ]]; then
  status="partial"
  summary="employee onboarding applied but one or more verification steps failed"
else
  status="success"
  summary="employee onboarding and verification completed"
fi

slack_result="skipped: SLACK_WEBHOOK_URL is not set"
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  slack_message="[homelab] employee onboarding $status: $username / $department / report=${report_path#$ROOT_DIR/}"
  SLACK_MESSAGE="$slack_message" python3 <<'PY'
import json, os, urllib.request
request = urllib.request.Request(
    os.environ["SLACK_WEBHOOK_URL"],
    data=json.dumps({"text": os.environ["SLACK_MESSAGE"]}).encode(),
    method="POST",
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(request, timeout=20) as response:
    if not 200 <= response.status < 300:
        raise RuntimeError(f"Slack returned HTTP {response.status}")
PY
  slack_rc=$?
  if [[ $slack_rc -eq 0 ]]; then
    slack_result="sent"
  else
    slack_result="failed (exit $slack_rc)"
    [[ "$status" != "success" ]] || status="partial"
    [[ "$summary" != "employee onboarding and verification completed" ]] || \
      summary="employee onboarding completed but Slack notification failed"
  fi
fi

ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
relative_report="${report_path#$ROOT_DIR/}"
ONBOARD_DB="$OPS_DB" ONBOARD_TARGET="$username" ONBOARD_STATUS="$status" \
ONBOARD_SUMMARY="$summary" ONBOARD_DEPARTMENT="$department" ONBOARD_GROUP="$group" \
ONBOARD_EMAIL="$email" ONBOARD_REPORT="$relative_report" ONBOARD_ONBOARD_RC="$onboard_rc" \
ONBOARD_WORKFLOW_VERIFY_RC="$onboarding_verify_rc" \
ONBOARD_SERVICE_VERIFY_RC="$service_verify_rc" ONBOARD_SLACK_RESULT="$slack_result" \
python3 <<'PY'
import datetime, json, os, pathlib, sqlite3
db_path = pathlib.Path(os.environ["ONBOARD_DB"])
db_path.parent.mkdir(parents=True, exist_ok=True)
details = {
    "department": os.environ["ONBOARD_DEPARTMENT"],
    "groups": [os.environ["ONBOARD_GROUP"]],
    "email": os.environ["ONBOARD_EMAIL"],
    "report_path": os.environ["ONBOARD_REPORT"],
    "verify_result": {
        "onboarding": int(os.environ["ONBOARD_WORKFLOW_VERIFY_RC"]),
        "services": int(os.environ["ONBOARD_SERVICE_VERIFY_RC"]),
    },
    "apply_return_code": int(os.environ["ONBOARD_ONBOARD_RC"]),
    "slack": os.environ["ONBOARD_SLACK_RESULT"],
}
with sqlite3.connect(db_path) as conn:
    conn.execute("""create table if not exists operations (
      id integer primary key autoincrement, created_at text not null,
      operation_type text not null, target text not null, status text not null,
      summary text not null, details_json text not null default '{}')""")
    conn.execute(
        "insert into operations(created_at, operation_type, target, status, summary, details_json) values (?, ?, ?, ?, ?, ?)",
        (datetime.datetime.now(datetime.timezone.utc).isoformat(), "employee_onboarding",
         os.environ["ONBOARD_TARGET"], os.environ["ONBOARD_STATUS"],
         os.environ["ONBOARD_SUMMARY"], json.dumps(details, sort_keys=True)),
    )
PY
db_rc=$?

if [[ $db_rc -eq 0 ]]; then
  db_result="recorded"
else
  db_result="failed (exit $db_rc)"
  if [[ "$status" == "success" ]]; then
    status="partial"
    summary="employee onboarding completed but SQLite recording failed"
  fi
fi

cat > "$report_path" <<EOF_REPORT
# Employee Onboarding Report

## Request Summary

- Username: \`$username\`
- Name: $given_name $surname
- Email: \`$email\`
- Department: \`$department\`
- Requested groups: \`$group\`
- Must change password: \`$must_change_password\`

## Execution Summary

- Status: \`$status\`
- Summary: $summary
- Playbook: \`ansible/playbooks/ad-onboard-user.yml\`
- Started: \`$started_at\`
- Ended: \`$ended_at\`
- Return code: \`$onboard_rc\`
- Log: \`${onboard_log#$ROOT_DIR/}\`

## Verification Summary

| Area | Result | Return code | Log |
|---|---|---:|---|
| Employee AD/Keycloak/Nextcloud/Mail | $([[ $onboarding_verify_rc -eq 0 ]] && echo passed || echo failed/skipped) | $onboarding_verify_rc | \`${onboarding_verify_log#$ROOT_DIR/}\` |
| AD/Keycloak/Nextcloud/Mail/Wazuh baseline | $([[ $service_verify_rc -eq 0 ]] && echo passed || echo failed/skipped) | $service_verify_rc | \`${service_verify_log#$ROOT_DIR/}\` |

## Notification Summary

- Slack: $slack_result
- Jira: skipped (not part of v1)
- GitHub: skipped (not part of v1)
- SQLite: $db_result

## Follow-up Actions

- Deliver the initial password through an approved secure channel.
- Provide the employee user guide.
- Perform a manual login test for Keycloak, Nextcloud, and mail.
- Review failed verification logs before retrying; v1 performs no automatic rollback.
EOF_REPORT

echo "Onboarding status: $status"
echo "Report: $report_path"
[[ "$status" == "success" && $db_rc -eq 0 ]]
