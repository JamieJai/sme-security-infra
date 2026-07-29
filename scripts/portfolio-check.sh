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
  docs/portfolio/endpoint-app-deployment-system-install.md
  docs/operations/employee-onboarding-runbook.md
  docs/operations/employee-offboarding-runbook.md
  docs/operations/helpdesk-scenarios.md
  scripts/onboard-employee.sh
  scripts/offboard-employee.sh
  scripts/helpdesk-diagnose.sh
  ansible/playbooks/employee-offboarding.yml
  ansible/playbooks/employee-offboarding-verify.yml
  ansible/playbooks/wazuh-custom-detections.yml
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
  "$ROOT_DIR/scripts/helpdesk-diagnose.sh" \
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

python3 -m unittest -q "$ROOT_DIR/tests/test_offboard_employee.py"
pass "offboarding plan and safety gates"

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
    playbooks/wazuh-agent-windows.yml "${vault_args[@]}"
  ansible-playbook -i inventory/hosts --syntax-check \
    playbooks/wazuh-custom-detections.yml "${vault_args[@]}"
)
pass "core Ansible playbook syntax"

printf 'Portfolio evidence checks passed: %d\n' "$checks"
