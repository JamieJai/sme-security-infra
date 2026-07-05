#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
ANSIBLE_DIR="$ROOT_DIR/ansible"
INVENTORY="${INVENTORY:-inventory/hosts}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
RUN_SERVICES="${RUN_SERVICES:-true}"
RUN_AGENT_DEPLOY="${RUN_AGENT_DEPLOY:-false}"
VAULT_ARGS=()

if [[ -f "$ANSIBLE_DIR/.vault_pass" ]]; then
  VAULT_ARGS=(--vault-password-file .vault_pass)
fi

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
}

confirm() {
  local prompt="$1"
  if [[ "$AUTO_APPROVE" == "true" ]]; then
    return 0
  fi
  read -r -p "$prompt [type APPLY to continue]: " answer
  [[ "$answer" == "APPLY" ]]
}

require_file "$TERRAFORM_DIR/terraform.tfvars"
require_file "$ANSIBLE_DIR/$INVENTORY"

if [[ ! -f "$ANSIBLE_DIR/.vault_pass" ]]; then
  echo "Warning: $ANSIBLE_DIR/.vault_pass not found. Vault-protected steps may fail." >&2
fi

cd "$TERRAFORM_DIR"
terraform init -input=false
terraform fmt -check -recursive
terraform validate
terraform plan -input=false -out=tfplan

confirm "Terraform apply may create or change infrastructure." || {
  echo "Aborted before terraform apply." >&2
  exit 1
}
terraform apply -input=false tfplan

cd "$ANSIBLE_DIR"
ansible all -i "$INVENTORY" -m ping

confirm "Apply Ansible baseline to managed hosts." || {
  echo "Aborted before Ansible baseline." >&2
  exit 1
}
ansible-playbook -i "$INVENTORY" site-baseline.yml -e @group_vars/all.yml "${VAULT_ARGS[@]}"

if [[ "$RUN_SERVICES" == "true" ]]; then
  confirm "Apply operational service configuration." || {
    echo "Aborted before Ansible services." >&2
    exit 1
  }
  ansible-playbook -i "$INVENTORY" site-services.yml -e @group_vars/all.yml "${VAULT_ARGS[@]}"
fi

if [[ "$RUN_AGENT_DEPLOY" == "true" ]]; then
  confirm "Deploy or reconcile Wazuh agents. This can install or downgrade wazuh-agent." || {
    echo "Aborted before Wazuh agent deploy." >&2
    exit 1
  }
  ansible-playbook -i "$INVENTORY" site-agent-deploy.yml -e @group_vars/all.yml "${VAULT_ARGS[@]}"
fi

ansible-playbook -i "$INVENTORY" playbooks/verify-all.yml "${VAULT_ARGS[@]}"
