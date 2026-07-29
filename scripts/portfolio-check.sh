#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"
checks=0

pass() {
  checks=$((checks + 1))
  printf 'PASS %s\n' "$1"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'FAIL required command not found: %s\n' "$1" >&2
    exit 1
  }
}

required_files=(
  README.md
  docs/portfolio/toss-it-manager-application.md
  docs/portfolio/resume-project-draft.md
  docs/portfolio/it-manager-demo-runbook.md
  docs/portfolio/employee-offboarding-lifecycle-pilot.md
  docs/portfolio/endpoint-app-deployment-system-install.md
  docs/operations/employee-onboarding-runbook.md
  docs/operations/employee-offboarding-runbook.md
  docs/operations/helpdesk-scenarios.md
  docs/operations/helpdesk-metrics-runbook.md
  docs/operations/asset-lifecycle-runbook.md
  scripts/onboard-employee.sh
  scripts/offboard-employee.sh
  scripts/recover-offboarded-employee.sh
  scripts/helpdesk-diagnose.sh
  scripts/helpdesk-ticket.py
  scripts/helpdesk-metrics.py
  scripts/asset-lifecycle.py
  scripts/it-manager-demo.sh
  scripts/ops_db.py
  ansible/playbooks/employee-offboarding.yml
  ansible/playbooks/employee-offboarding-verify.yml
  ansible/playbooks/employee-offboarding-recovery.yml
  ansible/playbooks/employee-offboarding-recovery-verify.yml
  ansible/playbooks/keycloak-user-session-pilot.yml
  ansible/files/samba_user_password.py
  ansible/playbooks/wazuh-custom-detections.yml
  tests/test_identity_playbook_safety.py
  tests/test_helpdesk_workflow.py
  tests/test_asset_lifecycle.py
  tests/test_register_endpoint.py
)

for command_name in git bash python3 ansible-playbook; do
  require_command "$command_name"
done

for relative_path in "${required_files[@]}"; do
  [[ -f "$ROOT_DIR/$relative_path" ]] || {
    printf 'FAIL required evidence file missing: %s\n' "$relative_path" >&2
    exit 1
  }
  git -C "$ROOT_DIR" ls-files --error-unmatch "$relative_path" >/dev/null
done
pass "application evidence files are present and tracked"

"$ROOT_DIR/scripts/check-no-secrets.sh"
pass "secret guard"

bash -n \
  "$ROOT_DIR/scripts/onboard-employee.sh" \
  "$ROOT_DIR/scripts/offboard-employee.sh" \
  "$ROOT_DIR/scripts/recover-offboarded-employee.sh" \
  "$ROOT_DIR/scripts/helpdesk-diagnose.sh" \
  "$ROOT_DIR/scripts/it-manager-demo.sh" \
  "$ROOT_DIR/scripts/verify-and-report.sh" \
  "$ROOT_DIR/scripts/portfolio-check.sh"
pass "shell syntax"

demo_dir="$(mktemp -d "${TMPDIR:-/tmp}/it-manager-portfolio.XXXXXX")"
trap 'rm -rf "$demo_dir"' EXIT
OPS_DB="$demo_dir/ops.sqlite" \
  "$ROOT_DIR/scripts/helpdesk-diagnose.sh" \
  --scenario sso \
  --username demo.user \
  --symptom "SSO login loop" \
  --network test-network \
  --occurred-at "2026-07-29 10:00 KST" \
  --output-dir "$demo_dir" >/dev/null
DEMO_DB="$demo_dir/ops.sqlite" python3 - <<'PY_DEMO'
import os
import sqlite3

with sqlite3.connect(os.environ["DEMO_DB"]) as db:
    row = db.execute(
        "select operation_type, target, status from operations order by id desc limit 1"
    ).fetchone()
assert row == ("helpdesk_diagnosis", "demo.user", "planned"), row
PY_DEMO
pass "isolated Helpdesk report and evidence record"

DEMO_DIR="$demo_dir/full-demo" "$ROOT_DIR/scripts/it-manager-demo.sh" >/dev/null
DEMO_DB="$demo_dir/full-demo/ops.sqlite" python3 - <<'PY_FULL_DEMO'
import os
import sqlite3

with sqlite3.connect(os.environ["DEMO_DB"]) as db:
    asset = db.execute(
        "select status, owner from assets where name = 'PC-DEMO01'"
    ).fetchone()
    ticket = db.execute(
        "select status, data_classification from helpdesk_tickets "
        "where ticket_ref = 'HD-DEMO-001'"
    ).fetchone()
    history_count = db.execute("select count(*) from asset_history").fetchone()[0]
    offboard_plan = db.execute(
        "select count(*) from operations "
        "where operation_type = 'employee_offboarding_plan'"
    ).fetchone()[0]
assert asset == ("assigned", "demo.user"), asset
assert ticket == ("resolved", "simulation"), ticket
assert history_count == 3, history_count
assert offboard_plan == 1, offboard_plan
PY_FULL_DEMO
pass "isolated end-to-end IT Manager demo"

python3 -m unittest -q "$ROOT_DIR/tests/test_helpdesk_workflow.py"
pass "Helpdesk ticket lifecycle and KPI tests"

python3 -m unittest -q "$ROOT_DIR/tests/test_asset_lifecycle.py"
pass "endpoint asset lifecycle safety gates"

python3 -m unittest -q "$ROOT_DIR/tests/test_register_endpoint.py"
pass "endpoint registration DB isolation and lifecycle guard"

python3 -m unittest -q "$ROOT_DIR/tests/test_offboard_employee.py"
pass "offboarding plan and safety gates"

python3 -m unittest -q "$ROOT_DIR/tests/test_recover_offboarded_employee.py"
pass "offboarding recovery plan and safety gates"

python3 -m unittest -q "$ROOT_DIR/tests/test_identity_playbook_safety.py"
pass "identity playbook safety invariants"

python3 -m unittest -q "$ROOT_DIR/tests/test_kali_egress_guard.py"
pass "Kali egress guard unit tests"

ROOT_DIR="$ROOT_DIR" python3 - <<'PY_XML'
import os
import pathlib
import xml.etree.ElementTree as ET

root = pathlib.Path(os.environ["ROOT_DIR"])
ET.parse(root / "ansible/files/wazuh/rules/sme_rules.xml")
decoders = (root / "ansible/files/wazuh/decoders/sme_decoders.xml").read_text()
ET.fromstring(f"<root>{decoders}</root>")
PY_XML
pass "Wazuh XML parse"

vault_args=()
[[ -f "$ANSIBLE_DIR/.vault_pass" ]] && vault_args=(--vault-password-file .vault_pass)

(
  cd "$ANSIBLE_DIR"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/employee-onboarding-verify.yml "${vault_args[@]}"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/employee-offboarding.yml "${vault_args[@]}"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/employee-offboarding-verify.yml "${vault_args[@]}"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/employee-offboarding-recovery.yml "${vault_args[@]}"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/employee-offboarding-recovery-verify.yml "${vault_args[@]}"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/keycloak-user-session-pilot.yml "${vault_args[@]}"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/wazuh-agent-windows.yml "${vault_args[@]}"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/wazuh-custom-detections.yml "${vault_args[@]}"
)
pass "core Ansible playbook syntax"

printf 'Portfolio evidence checks passed: %d\n' "$checks"
