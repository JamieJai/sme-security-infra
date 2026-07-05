#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"

cd "$TERRAFORM_DIR"

terraform init -input=false
terraform fmt -check -recursive
terraform validate
terraform plan -input=false
