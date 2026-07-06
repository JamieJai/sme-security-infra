#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"
REPORT_DIR="$ROOT_DIR/reports/it-health"
OPS_DB="$ROOT_DIR/.codex/mcp/homelab_ops.sqlite"
INVENTORY="${INVENTORY:-inventory/hosts}"
PUBLISH_NOTION="${PUBLISH_NOTION:-false}"
SLACK_CHANNEL="${SLACK_CHANNEL:-}"

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/verify-and-report.sh [--publish-notion]

Runs IT health verification, writes a Markdown report, records the result in
.codex/mcp/homelab_ops.sqlite, sends Slack when SLACK_WEBHOOK_URL is set, and
optionally publishes the report to Notion when NOTION_TOKEN and
NOTION_PARENT_PAGE_ID are set.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --publish-notion)
      PUBLISH_NOTION=true
      shift
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

mkdir -p "$REPORT_DIR"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
report_path="$REPORT_DIR/$timestamp-it-health.md"
log_path="$REPORT_DIR/$timestamp-verify-all.log"
relative_report="${report_path#$ROOT_DIR/}"
relative_log="${log_path#$ROOT_DIR/}"

vault_args=()
[[ -f "$ANSIBLE_DIR/.vault_pass" ]] && vault_args=(--vault-password-file .vault_pass)

(
  cd "$ANSIBLE_DIR"
  ansible-playbook -i "$INVENTORY" playbooks/verify-all.yml "${vault_args[@]}"
) 2>&1 | tee "$log_path"
run_rc="${PIPESTATUS[0]}"

ended_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [[ "$run_rc" -eq 0 ]]; then
  status="success"
  summary="IT health verification completed successfully"
else
  status="failed"
  summary="IT health verification failed; review $relative_log"
fi

failed_count="$(grep -E "failed=[1-9]" "$log_path" | wc -l | tr -d ' ')"
unreachable_count="$(grep -E "unreachable=[1-9]" "$log_path" | wc -l | tr -d ' ')"
changed_count="$(grep -E "changed=[1-9]" "$log_path" | wc -l | tr -d ' ')"

cat > "$report_path" <<EOF_REPORT
# IT Health Report

## Summary

- Status: \`$status\`
- Summary: $summary
- Started: \`$started_at\`
- Ended: \`$ended_at\`
- Verification log: \`$relative_log\`

## Ansible Result Indicators

- Recap lines with failed hosts: \`$failed_count\`
- Recap lines with unreachable hosts: \`$unreachable_count\`
- Recap lines with changed hosts: \`$changed_count\`

## Scope

- AD replication, DNS, FSMO, account policy
- Keycloak/LDAP/OIDC baseline
- Nextcloud status, background jobs, Mail app, Talk app
- Mail service and ports
- Wazuh manager, indexer, dashboard, agent/log baselines
- Backup, restore, certificate, RBAC, custom detection baselines where covered by \`verify-all.yml\`

## Follow-up

- If status is \`failed\`, inspect \`$relative_log\` and open a helpdesk/operations issue.
- If the issue is user-facing, document cause, impact, mitigation, root fix, and recurrence prevention.
- Publish this report to Notion only after confirming it contains no secrets or raw sensitive log content.
EOF_REPORT

SLACK_RESULT="skipped: SLACK_WEBHOOK_URL is not set"
if [[ -n "${SLACK_WEBHOOK_URL:-}" ]]; then
  slack_text="[homelab] IT health $status: $summary / report=$relative_report"
  SLACK_MESSAGE="$slack_text" SLACK_CHANNEL="$SLACK_CHANNEL" python3 <<'PY_SLACK'
import json, os, urllib.request
payload = {"text": os.environ["SLACK_MESSAGE"]}
if os.environ.get("SLACK_CHANNEL"):
    payload["channel"] = os.environ["SLACK_CHANNEL"]
request = urllib.request.Request(
    os.environ["SLACK_WEBHOOK_URL"],
    data=json.dumps(payload).encode(),
    method="POST",
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(request, timeout=20) as response:
    if not 200 <= response.status < 300:
        raise RuntimeError(f"Slack returned HTTP {response.status}")
PY_SLACK
  slack_rc=$?
  if [[ "$slack_rc" -eq 0 ]]; then
    SLACK_RESULT="sent"
  else
    SLACK_RESULT="failed (exit $slack_rc)"
    [[ "$status" != "success" ]] || status="partial"
  fi
fi

NOTION_RESULT="skipped"
if [[ "$PUBLISH_NOTION" == "true" ]]; then
  if [[ -z "${NOTION_TOKEN:-}" || -z "${NOTION_PARENT_PAGE_ID:-}" ]]; then
    NOTION_RESULT="skipped: NOTION_TOKEN or NOTION_PARENT_PAGE_ID is not set"
  else
    NOTION_TITLE="IT Health Report $timestamp" NOTION_CONTENT="$(cat "$report_path")" python3 <<'PY_NOTION'
import json, os, ssl, urllib.request

def block(text, block_type="paragraph"):
    return {
        "object": "block",
        "type": block_type,
        block_type: {"rich_text": [{"type": "text", "text": {"content": text[:1800]}}]},
    }

children = []
for raw in os.environ["NOTION_CONTENT"].splitlines():
    line = raw.strip()
    if not line:
        continue
    if line.startswith("# "):
        children.append(block(line[2:].strip(), "heading_1"))
    elif line.startswith("## "):
        children.append(block(line[3:].strip(), "heading_2"))
    elif line.startswith("- "):
        children.append(block(line[2:].strip(), "bulleted_list_item"))
    else:
        children.append(block(line, "paragraph"))
children = children[:90]
payload = {
    "parent": {"page_id": os.environ["NOTION_PARENT_PAGE_ID"]},
    "properties": {"title": {"title": [{"text": {"content": os.environ["NOTION_TITLE"]}}]}},
    "children": children,
}
request = urllib.request.Request(
    "https://api.notion.com/v1/pages",
    data=json.dumps(payload).encode(),
    method="POST",
    headers={
        "Authorization": f"Bearer {os.environ['NOTION_TOKEN']}",
        "Notion-Version": "2026-03-11",
        "Content-Type": "application/json",
        "Accept": "application/json",
    },
)
with urllib.request.urlopen(request, timeout=20, context=ssl.create_default_context()) as response:
    if not 200 <= response.status < 300:
        raise RuntimeError(f"Notion returned HTTP {response.status}")
PY_NOTION
    notion_rc=$?
    if [[ "$notion_rc" -eq 0 ]]; then
      NOTION_RESULT="published"
    else
      NOTION_RESULT="failed (exit $notion_rc)"
      [[ "$status" != "success" ]] || status="partial"
    fi
  fi
fi

OPS_DB="$OPS_DB" STATUS="$status" SUMMARY="$summary" REPORT="$relative_report" LOG="$relative_log" RUN_RC="$run_rc" SLACK_RESULT="$SLACK_RESULT" NOTION_RESULT="$NOTION_RESULT" python3 <<'PY_DB'
import datetime, json, os, pathlib, sqlite3
path = pathlib.Path(os.environ["OPS_DB"])
path.parent.mkdir(parents=True, exist_ok=True)
details = {
    "report_path": os.environ["REPORT"],
    "log_path": os.environ["LOG"],
    "return_code": int(os.environ["RUN_RC"]),
    "slack": os.environ["SLACK_RESULT"],
    "notion": os.environ["NOTION_RESULT"],
}
with sqlite3.connect(path) as conn:
    conn.execute("""create table if not exists operations (
      id integer primary key autoincrement, created_at text not null,
      operation_type text not null, target text not null, status text not null,
      summary text not null, details_json text not null default '{}')""")
    conn.execute(
        "insert into operations(created_at, operation_type, target, status, summary, details_json) values (?, ?, ?, ?, ?, ?)",
        (datetime.datetime.now(datetime.timezone.utc).isoformat(), "it_health_verify", "homelab", os.environ["STATUS"], os.environ["SUMMARY"], json.dumps(details, sort_keys=True)),
    )
PY_DB
DB_RC=$?

cat <<EOF
IT health status: $status
Report: $report_path
Log: $log_path
Slack: $SLACK_RESULT
Notion: $NOTION_RESULT
SQLite: $([[ "$DB_RC" -eq 0 ]] && echo recorded || echo "failed (exit $DB_RC)")
EOF

[[ "$run_rc" -eq 0 && "$DB_RC" -eq 0 ]]
