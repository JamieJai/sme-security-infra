# Codex Operating Rules for homelab-infra

This repository is an IT operations automation portfolio, not a disposable lab. Treat Codex as an IT Manager assistant that helps operate, verify, document, and improve the environment.

## Core Rules

- Prior check: read the existing code, playbooks, scripts, and docs before editing. Reuse local patterns first.
- Idempotency: Ansible playbooks, Terraform changes, and scripts must remain repeatable and converge safely.
- Documentation: when behavior, workflow, infrastructure, or operating assumptions change, update the relevant runbook in the same change.
- Safety first: do not apply production-impacting changes without explicit approval. For risky changes, explain rollback or recovery before execution.
- GitOps hygiene: prefer feature branches, focused commits, and PR-ready summaries for operational changes.
- Verification: run the smallest meaningful syntax, plan, lint, or verify command available. Store important verification outcomes in the operations DB when the MCP tooling is available.
- Secrets: never commit secrets, decrypted vault values, tfstate contents, API tokens, app passwords, or webhook URLs. Use environment variables or vault-backed files.

## MCP Use

Use MCP tools when they provide better operating context than raw shell commands:

- `homelab` MCP for project files, GitOps helpers, SQLite operations data, service health, Proxmox, Docker, Slack, Jira, and GitHub API helpers.
- `ansible_homelab` MCP for Ansible-specific inventory/playbook context.
- `trivy` MCP for vulnerability and IaC/container security scanning.
- `playwright` MCP for browser-based Keycloak, Nextcloud, Mail UI, and admin console verification.
- `openaiDeveloperDocs` and `context7` MCPs for current official/platform/library documentation.

If an MCP server is unavailable, continue with local CLI tools and document the limitation in the final result.
