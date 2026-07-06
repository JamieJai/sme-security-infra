# MCP Roadmap for IT Manager Homelab

## Goal

This project targets an internal IT operations automation portfolio. Codex should act less like a code generator and more like an IT Manager assistant: inspect the current operating state, make controlled infrastructure changes, verify the result, update runbooks, and prepare GitOps delivery artifacts.

## Priority Map

| Priority | MCP area | Status | Purpose | Implementation |
|---|---:|---|---|---|
| 1 | Filesystem | Active | Explore and update docs, Ansible, Terraform, scripts, and reports | `homelab` MCP tools: `project_tree`, `read_project_file`, `write_project_file` |
| 2 | GitHub / GitOps | Partial | Branch, commit, PR, README/CHANGELOG, issues | `homelab` MCP local git tools plus GitHub REST helpers; official GitHub MCP is configured disabled until Docker image/token are ready |
| 3 | Database | Active | Store and query IT assets and operational state | Local SQLite DB at `.codex/mcp/homelab_ops.sqlite` via `ops_db_*` MCP tools |
| 4 | Slack | Token-ready | Notify verify failures, onboarding completion, certificate expiry, backup failures | `slack_notify` uses `SLACK_WEBHOOK_URL` |
| 5 | Jira | Token-ready | Create helpdesk/ITSM tickets and map incidents to runbooks | `jira_create_issue` uses Jira env vars |
| 6 | Playwright | Configured | E2E verification for Keycloak, Nextcloud, Mail UI, admin consoles | `playwright` MCP via `npx -y @playwright/mcp` |
| 7 | Docker | CLI-ready when installed | Container status, logs, health check, restart | `docker_*` MCP tools; current host has no Docker CLI |
| 8 | Proxmox | Token-ready | VM inventory, node status, later snapshots/power operations | `proxmox_*` read tools use Proxmox token env vars |

## Current MCP Servers

| Server | Role | Notes |
|---|---|---|
| `homelab` | Project-specific IT operations MCP | Main integration layer for files, Git, DB, service health, Slack, Jira, Docker, Proxmox |
| `ansible_homelab` | Ansible MCP | Points at `ansible/inventory/hosts` and `ansible/roles` |
| `trivy` | Security scanning MCP | Uses local Trivy plugin and binary path |
| `playwright` | Browser E2E MCP | First run may download npm package/browser assets |
| `openaiDeveloperDocs` | OpenAI documentation | Official OpenAI docs MCP |
| `context7` | Library/tool documentation | First run may download npm package |
| `github` | Official GitHub MCP | Configured disabled until Docker and GitHub token are ready |

## Required Environment Variables

Only export the variables needed for the workflow being performed. Do not store these values in git.

| Area | Variables |
|---|---|
| GitHub REST helpers | `GITHUB_TOKEN` |
| Official GitHub MCP | `GITHUB_PERSONAL_ACCESS_TOKEN` |
| Slack | `SLACK_WEBHOOK_URL` |
| Jira | `JIRA_BASE_URL`, `JIRA_EMAIL`, `JIRA_API_TOKEN`, `JIRA_PROJECT_KEY` |
| Wazuh | `WAZUH_URL`, `WAZUH_USER`, `WAZUH_PASSWORD` |
| Nextcloud | `NEXTCLOUD_URL`, `NEXTCLOUD_USER`, `NEXTCLOUD_APP_PASSWORD` |
| Keycloak | `KEYCLOAK_URL`, `KEYCLOAK_REALM`, `KEYCLOAK_ADMIN_USER`, `KEYCLOAK_ADMIN_PASSWORD` |
| Proxmox | `PROXMOX_URL`, `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET` |

## Operating Workflow: Employee Onboarding

1. GitOps: check current branch and status, then create a feature branch.
2. Prior check: read existing onboarding playbooks, inventory, group vars, and runbooks.
3. IaC and configuration: update Terraform/Ansible/docs with idempotent changes.
4. Validation: run syntax checks, Terraform validation/plan when relevant, and service verify scripts.
5. Database: record verification and onboarding operation results in SQLite.
6. Notification: send Slack notification for completion or failure when webhook is configured.
7. Helpdesk: create or update Jira/GitHub issue if the task came from an incident or request.
8. Delivery: commit focused changes and prepare PR summary.

## Safety Rules

- Read-only inspection is allowed by default.
- `terraform apply`, destructive Ansible playbooks, VM power operations, Docker restarts, account disable/delete, and credential rotation require explicit approval.
- For any risky operation, prepare a rollback/recovery path before running it.
- Verification failures should be captured in the operations DB with enough detail to support later trend analysis.
- Runbook updates are part of the definition of done for workflow or environment changes.

## Next Hardening Steps

1. Install or enable Docker CLI if Docker MCP operations should run on this host.
2. Export GitHub token and enable the official `github` MCP after confirming Docker can pull `ghcr.io/github/github-mcp-server`.
3. Add scheduled verification jobs that write to `.codex/mcp/homelab_ops.sqlite`.
4. Add Slack/Jira notification wrappers to `scripts/verify-all.sh` or a dedicated reporting script.
5. Extend Proxmox tools from read-only inventory/status to approved snapshot and power actions.
6. Add Playwright E2E scripts for Keycloak login, Nextcloud login, OIDC flow, and admin console checks.
