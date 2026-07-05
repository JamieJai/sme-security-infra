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

ansible all -i "$INVENTORY" -m ping
ansible-playbook -i "$INVENTORY" playbooks/ad-dns-records.yml "${VAULT_ARGS[@]}"
ansible-playbook -i "$INVENTORY" playbooks/verify-all.yml "${VAULT_ARGS[@]}"
