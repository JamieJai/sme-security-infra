#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANSIBLE_DIR="$ROOT_DIR/ansible"
INVENTORY="${INVENTORY:-inventory/hosts}"
VAULT_ARGS=()

if [[ -f "$ANSIBLE_DIR/.vault_pass" ]]; then
  VAULT_ARGS=(--vault-password-file .vault_pass)
fi

cd "$ANSIBLE_DIR"

ansible-playbook -i "$INVENTORY" site-agent-deploy.yml -e @group_vars/all.yml "${VAULT_ARGS[@]}"
