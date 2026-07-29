#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"
REPORT_DIR="$ROOT_DIR/artifacts/helpdesk"
OPS_DB="${OPS_DB:-$ROOT_DIR/.codex/mcp/homelab_ops.sqlite}"
INVENTORY="${INVENTORY:-inventory/hosts}"

scenario=""
username=""
computer_name=""
symptom=""
network=""
occurred_at=""
execute=false
output_dir=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/helpdesk-diagnose.sh \
    --scenario domain-join|ad-login|sso|nextcloud-folder|mail-login|it-health \
    [--username USERNAME] \
    [--computer-name COMPUTER_NAME] \
    [--symptom TEXT] \
    [--network TEXT] \
    [--occurred-at TEXT] \
    [--execute] \
    [--output-dir DIR]

Creates a Markdown helpdesk diagnosis report from docs/operations/helpdesk-scenarios.md.
By default it only writes the triage plan and read-only command list. With --execute,
it runs the documented read-only Ansible checks and stores command logs.

No password, ODJ blob, token, webhook, or vault value should be passed to this script.
USAGE
}

die() {
  echo "Error: $*" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario|--username|--computer-name|--symptom|--network|--occurred-at|--output-dir)
      [[ $# -ge 2 ]] || die "$1 requires a value"
      case "$1" in
        --scenario) scenario="$2" ;;
        --username) username="$2" ;;
        --computer-name) computer_name="$2" ;;
        --symptom) symptom="$2" ;;
        --network) network="$2" ;;
        --occurred-at) occurred_at="$2" ;;
        --output-dir) output_dir="$2" ;;
      esac
      shift 2
      ;;
    --execute)
      execute=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
done

[[ -n "$scenario" ]] || die "--scenario is required"
case "$scenario" in
  domain-join|ad-login|sso|nextcloud-folder|mail-login|it-health) ;;
  *) die "unsupported scenario: $scenario" ;;
esac

if [[ -n "$username" ]]; then
  [[ "$username" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || die "--username contains unsupported characters"
fi
if [[ -n "$computer_name" ]]; then
  [[ "$computer_name" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,14}$ ]] || die "--computer-name must be 1-15 letters, digits, or hyphen"
fi
for value in "$symptom" "$network" "$occurred_at"; do
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "free-text values must be single-line"
done

[[ -f "$ANSIBLE_DIR/$INVENTORY" ]] || die "inventory not found: $ANSIBLE_DIR/$INVENTORY"
command -v python3 >/dev/null 2>&1 || die "python3 is required"
if [[ "$execute" == "true" ]]; then
  command -v ansible >/dev/null 2>&1 || die "ansible is required for --execute"
  command -v ansible-playbook >/dev/null 2>&1 || die "ansible-playbook is required for --execute"
fi

[[ -n "$output_dir" ]] && REPORT_DIR="$output_dir"
mkdir -p "$REPORT_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
created_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
target="${username:-${computer_name:-homelab}}"
safe_target="$(printf '%s' "$target" | tr -cd 'A-Za-z0-9_.-' | tr '[:upper:]' '[:lower:]')"
[[ -n "$safe_target" ]] || safe_target="homelab"
report_path="$REPORT_DIR/$timestamp-$scenario-$safe_target.md"
log_dir="$REPORT_DIR/$timestamp-$scenario-$safe_target-logs"
mkdir -p "$log_dir"
asset_context_path="$log_dir/asset-context.md"

HELPDESK_DB="$OPS_DB" HELP_USER="$username" HELP_COMPUTER="$computer_name" python3 > "$asset_context_path" <<'PY_ASSET'
import json, os, pathlib, sqlite3

db_path = pathlib.Path(os.environ["HELPDESK_DB"])
username = os.environ.get("HELP_USER", "")
computer = os.environ.get("HELP_COMPUTER", "")
print("## Asset Context")
print()
if not db_path.exists():
    print("- No operations DB found yet.")
    raise SystemExit
clauses = []
params = []
if computer:
    clauses.append("name = ?")
    params.append(computer)
if username:
    clauses.append("owner = ?")
    params.append(username)
if not clauses:
    print("- No username or computer name was provided for asset lookup.")
    raise SystemExit
query = "select name, kind, status, owner, metadata_json, updated_at from assets where " + " or ".join(clauses) + " order by updated_at desc limit 5"
try:
    with sqlite3.connect(db_path) as conn:
        rows = conn.execute(query, params).fetchall()
except sqlite3.OperationalError:
    rows = []
if not rows:
    print("- No matching endpoint asset record found.")
    raise SystemExit
for name, kind, status, owner, metadata_json, updated_at in rows:
    try:
        metadata = json.loads(metadata_json or "{}")
    except json.JSONDecodeError:
        metadata = {}
    print(f"- Asset: `{name}`")
    print(f"  - kind: `{kind}`")
    print(f"  - status: `{status}`")
    print(f"  - owner: `{owner or 'unassigned'}`")
    print(f"  - updated_at: `{updated_at}`")
    for key in ("employee_id", "department", "asset_tag", "serial_number", "join_method", "package_path", "report_path"):
        if metadata.get(key):
            print(f"  - {key}: `{metadata[key]}`")
PY_ASSET

vault_args=()
[[ -f "$ANSIBLE_DIR/.vault_pass" ]] && vault_args=(--vault-password-file .vault_pass)

scenario_title=""
required_context=()
manual_checks=()
commands=()
followups=()

add_command() {
  commands+=("$1")
}

case "$scenario" in
  domain-join)
    scenario_title="Windows PC 도메인 가입 실패"
    required_context=("PC name" "network" "error message" "ODJ package path, if applicable")
    manual_checks=(
      "사용자 PC에서 hostname, DNS server, Resolve-DnsName toss.lan, Resolve-DnsName dc02.toss.lan 확인"
      "ODJ package의 Computer Name과 실제 hostname 일치 여부 확인"
      "odj.blob을 다른 PC에 재사용하지 않았는지 확인"
    )
    [[ -n "$computer_name" ]] && add_command "ansible active_dc -i ansible/inventory/hosts -b -m command -a 'samba-tool computer show $computer_name'"
    followups=("DNS가 AD DNS가 아니면 192.168.0.21,192.168.0.20 기준으로 보정" "hostname 불일치 시 기존 blob 재사용 금지, 새 computer name으로 재발급" "잘못 배포된 package는 회수하고 AD computer object disable/delete는 승인 후 수행")
    ;;
  ad-login)
    scenario_title="도메인 가입 후 AD 로그인 실패"
    required_context=("username" "PC name" "network" "login error message")
    manual_checks=(
      "사용자 PC에서 PartOfDomain, nltest /dsgetdc:toss.lan, klist 확인"
      "사내망/VPN에서 AD DNS/DC 접근 가능 여부 확인"
    )
    [[ -n "$computer_name" ]] && add_command "ansible active_dc -i ansible/inventory/hosts -b -m command -a 'samba-tool computer show $computer_name'"
    [[ -n "$username" ]] && add_command "ansible active_dc -i ansible/inventory/hosts -b -m command -a 'samba-tool user show $username'"
    followups=("DC discovery 실패 시 네트워크/VPN/DNS부터 보정" "사용자 계정 disabled/password expired 상태면 계정 lifecycle runbook으로 이관" "trust relationship 재설정은 운영 변경 승인 후 수행")
    ;;
  sso)
    scenario_title="Keycloak SSO 로그인 실패"
    required_context=("username" "service URL" "login time" "OIDC error message")
    manual_checks=("다른 사용자도 실패하는지 확인" "Nextcloud OIDC callback 이후 어디서 멈추는지 확인")
    [[ -n "$username" ]] && add_command "ansible active_dc -i ansible/inventory/hosts -b -m command -a 'samba-tool user show $username'"
    add_command "cd ansible && ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags identity,keycloak ${vault_args[*]}"
    add_command "ansible keycloak -i ansible/inventory/hosts -b -m command -a 'systemctl is-active keycloak'"
    followups=("단일 사용자 실패면 AD 속성/그룹/mail/displayName 확인" "전체 실패면 Keycloak service, LDAP federation, LDAPS/HAProxy 경로 확인" "OIDC client/secret/redirect 변경은 승인 후 수행")
    ;;
  nextcloud-folder)
    scenario_title="Nextcloud 부서 폴더 미노출"
    required_context=("username" "department" "expected folder" "recent department change")
    manual_checks=("사용자 로그아웃/재로그인 여부 확인" "다른 브라우저에서도 동일한지 확인" "같은 부서 다른 사용자 영향 여부 확인")
    [[ -n "$username" ]] && add_command "ansible active_dc -i ansible/inventory/hosts -b -m command -a 'samba-tool user show $username'"
    add_command "cd ansible && ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags identity,nextcloud ${vault_args[*]}"
    followups=("AD group 문제면 온보딩/부서 이동 workflow로 보정" "AD group은 맞으면 Keycloak groups claim과 Nextcloud OIDC group provisioning 확인" "external storage 변경은 영향 범위 확인 후 승인받아 수행")
    ;;
  mail-login)
    scenario_title="Mail 로그인 실패"
    required_context=("username" "mail address" "client type" "error message")
    manual_checks=("사용자 비밀번호를 수집하지 않는다" "Nextcloud Mail만 실패하는지 별도 IMAP client도 실패하는지 확인")
    [[ -n "$username" ]] && add_command "ansible active_dc -i ansible/inventory/hosts -b -m command -a 'samba-tool user show $username'"
    add_command "cd ansible && ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags mail ${vault_args[*]}"
    add_command "ansible mail_server -i ansible/inventory/hosts -b -m command -a 'systemctl is-active postfix'"
    add_command "ansible mail_server -i ansible/inventory/hosts -b -m command -a 'systemctl is-active dovecot'"
    followups=("mail attribute 누락이면 온보딩 workflow로 보정" "Dovecot LDAPS auth 또는 mail map 문제면 영향 범위 확인" "mail service 변경은 승인 후 수행")
    ;;
  it-health)
    scenario_title="전체 IT health 검증 실패"
    required_context=("failed report path" "first failed task" "affected services")
    manual_checks=("첫 실패 task의 host/stdout/stderr 확인" "단일 서비스 장애인지 공통 dependency 장애인지 분리")
    add_command "cd ansible && ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags ad ${vault_args[*]}"
    add_command "cd ansible && ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags keycloak,nextcloud ${vault_args[*]}"
    add_command "cd ansible && ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags mail ${vault_args[*]}"
    add_command "cd ansible && ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags wazuh ${vault_args[*]}"
    followups=("단일 서비스 실패면 해당 service runbook으로 이관" "여러 서비스 동시 실패면 DNS/AD/network/storage 확인" "복구 playbook은 별도 승인 후 실행")
    ;;
esac

run_status="planned"
failed_commands=0
executed_commands=0
command_results=()

run_command() {
  local index="$1"
  local command_text="$2"
  local log_path="$log_dir/$(printf '%02d' "$index").log"
  echo "# $command_text" > "$log_path"
  set +e
  (cd "$ROOT_DIR" && bash -lc "$command_text") >> "$log_path" 2>&1
  local rc=$?
  set -e
  command_results+=("$index|$rc|${log_path#$ROOT_DIR/}")
  executed_commands=$((executed_commands + 1))
  if [[ "$rc" -ne 0 ]]; then
    failed_commands=$((failed_commands + 1))
  fi
}

if [[ "$execute" == "true" ]]; then
  run_status="success"
  if [[ "${#commands[@]}" -eq 0 ]]; then
    run_status="partial"
  else
    i=1
    for command_text in "${commands[@]}"; do
      run_command "$i" "$command_text"
      i=$((i + 1))
    done
    [[ "$failed_commands" -eq 0 ]] || run_status="partial"
  fi
fi

summary="Helpdesk diagnosis $run_status for $scenario"
relative_report="${report_path#$ROOT_DIR/}"
relative_log_dir="${log_dir#$ROOT_DIR/}"

{
  echo "# Helpdesk Diagnosis Report"
  echo
  echo "## Summary"
  echo
  echo "- Scenario: \`$scenario\` - $scenario_title"
  echo "- Status: \`$run_status\`"
  echo "- Created: \`$created_at\`"
  echo "- Username: \`${username:-not provided}\`"
  echo "- Computer name: \`${computer_name:-not provided}\`"
  echo "- Network: ${network:-not provided}"
  echo "- Occurred at: ${occurred_at:-not provided}"
  echo "- Symptom: ${symptom:-not provided}"
  echo "- Logs: \`$relative_log_dir\`"
  echo
  if [[ -s "$asset_context_path" ]]; then
    cat "$asset_context_path"
    echo
  fi
  echo "## Required Context"
  echo
  for item in "${required_context[@]}"; do
    echo "- $item"
  done
  echo
  echo "## Manual Checks"
  echo
  for item in "${manual_checks[@]}"; do
    echo "- $item"
  done
  echo
  echo "## Read-only Commands"
  echo
  if [[ "${#commands[@]}" -eq 0 ]]; then
    echo "- No server-side read-only command could be built from the provided inputs."
  else
    for command_text in "${commands[@]}"; do
      echo "- \`$command_text\`"
    done
  fi
  echo
  echo "## Execution Results"
  echo
  if [[ "$execute" != "true" ]]; then
    echo "- Not executed. Re-run with \`--execute\` to run read-only checks."
  elif [[ "${#command_results[@]}" -eq 0 ]]; then
    echo "- No commands executed. Provide required context such as username or computer name when needed."
  else
    for result in "${command_results[@]}"; do
      IFS='|' read -r index rc log_path <<< "$result"
      echo "- Command $index: rc=\`$rc\`, log=\`$log_path\`"
    done
  fi
  echo
  echo "## Initial Assessment"
  echo
  echo "- likely_cause: TBD after reviewing checks"
  echo "- impact: TBD"
  echo "- temporary_action: TBD"
  echo "- permanent_action: TBD"
  echo
  echo "## Follow-up"
  echo
  for item in "${followups[@]}"; do
    echo "- $item"
  done
  echo
  echo "## Evidence Handling"
  echo
  echo "- Do not paste passwords, ODJ blobs, tokens, webhook URLs, vault values, or raw sensitive logs into Slack/Notion."
  echo "- AD object cleanup, account changes, service restarts, firewall changes, and Terraform apply require approval."
} > "$report_path"

HELPDESK_DB="$OPS_DB" HELP_TARGET="$target" HELP_STATUS="$run_status" HELP_SUMMARY="$summary" \
HELP_SCENARIO="$scenario" HELP_REPORT="$relative_report" HELP_LOG_DIR="$relative_log_dir" \
HELP_EXECUTE="$execute" HELP_FAILED="$failed_commands" HELP_EXECUTED="$executed_commands" python3 <<'PY_DB'
import datetime, json, os, pathlib, sqlite3
path = pathlib.Path(os.environ["HELPDESK_DB"])
path.parent.mkdir(parents=True, exist_ok=True)
details = {
    "scenario": os.environ["HELP_SCENARIO"],
    "report_path": os.environ["HELP_REPORT"],
    "log_dir": os.environ["HELP_LOG_DIR"],
    "execute": os.environ["HELP_EXECUTE"] == "true",
    "commands_executed": int(os.environ["HELP_EXECUTED"]),
    "commands_failed": int(os.environ["HELP_FAILED"]),
}
with sqlite3.connect(path) as conn:
    conn.execute("""create table if not exists operations (
      id integer primary key autoincrement, created_at text not null,
      operation_type text not null, target text not null, status text not null,
      summary text not null, details_json text not null default '{}')""")
    conn.execute(
        "insert into operations(created_at, operation_type, target, status, summary, details_json) values (?, ?, ?, ?, ?, ?)",
        (datetime.datetime.now(datetime.timezone.utc).isoformat(), "helpdesk_diagnosis",
         os.environ["HELP_TARGET"], os.environ["HELP_STATUS"], os.environ["HELP_SUMMARY"],
         json.dumps(details, sort_keys=True)),
    )
PY_DB

echo "Helpdesk diagnosis: $run_status"
echo "Report: $report_path"
echo "Logs: $log_dir"
echo "SQLite: recorded"

if [[ "$execute" == "true" && "$failed_commands" -gt 0 ]]; then
  exit 1
fi
