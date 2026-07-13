# Session Handoff - 2026-07-13 Wazuh Windows Endpoint and Kali Plan

Repo: `/home/sysadmin/homelab-infra`

This handoff preserves the state after fixing Wazuh access, Windows endpoint Wazuh enrollment, and planning the next Kali-based purple-team validation. Do not include secrets in follow-up notes.

## Current State

- Wazuh Dashboard/admin credential issue was fixed by rotating `wazuh_admin_password` and `wazuh_breakglass_password` in `ansible/group_vars/wazuh-rbac-vault.yml`.
  - Prior values had a trailing newline and could not be typed cleanly into the Dashboard.
  - New vaulted values are 48 chars each and do not end with newline.
  - `ansible-playbook -i inventory/hosts playbooks/wazuh-rbac.yml --vault-password-file .vault_pass` succeeded and verified both internal users.
- Stale Wazuh agent `windows-test` was removed from manager with `manage_agents` after verifying it was disconnected.
- `keycloak` remains active as Wazuh agent `ID 007`.
- Windows SSH access was recovered for both endpoint VMs using Proxmox API + QEMU Guest Agent.
  - Proxmox API creds were read from local `terraform/terraform.tfvars`; values were not printed.
  - QEMU Guest Agent was active on VMID 109 and 110.
  - automation01 public keys were written to `C:\ProgramData\ssh\administrators_authorized_keys`.
  - `sshd` was restarted.
  - `ansible windows_management:windows_endpoint_pilot -e ansible_become=false -m ansible.windows.win_ping` succeeded.
- Windows Wazuh agent was installed and started on:
  - `WIN-MGMT01` / `192.168.0.76` / Proxmox VMID `109`
  - `ODJ-VERIFY01` / `192.168.0.77` / Proxmox VMID `110`
- Wazuh manager-side `windows` agent group was created. Initial enrollment failed before this because Windows agents received `Invalid group: windows (from manager)`.
- Final Wazuh manager agent state:
  - `ID 008, Name: ODJ-VERIFY01, Active`
  - `ID 009, Name: WIN-MGMT01, Active`
- Final verification command succeeded:

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags wazuh --vault-password-file .vault_pass
```

## Code/Runbook Changes Made This Session

Important changes made or prepared:

- `ansible/inventory/hosts`
  - Added `linux_managed` group so Linux Wazuh playbooks do not target Windows hosts.
  - Added `ansible_become=false` for Windows groups.
- `ansible/playbooks/wazuh-agent-deploy.yml`
  - Now targets `linux_managed` instead of `all:!wazuh_server`.
- `ansible/playbooks/wazuh-agent-logs.yml`
  - Now targets `linux_managed`.
- `ansible/playbooks/wazuh-agent-windows.yml`
  - New Windows Wazuh agent playbook.
  - Creates manager-side `windows` group before endpoint enrollment.
  - Installs Wazuh agent MSI and verifies `WazuhSvc` is running.
- `ansible/playbooks/endpoint-onboarding.yml`
  - New wrapper importing `wazuh-agent-windows.yml` so endpoint onboarding has a Wazuh visibility phase.
- `ansible/playbooks/verify-all.yml`
  - Linux baseline and Windows endpoint Wazuh checks are split.
  - `--tags wazuh` checks Windows `WazuhSvc` and Wazuh manager active agent list.
- `endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1`
  - ODJ apply script now installs/enrolls Wazuh agent before applying ODJ.
  - Supports `-WazuhManager`, `-WazuhAgentVersion`, `-WazuhAgentGroup`, `-WazuhMsiPath`, `-SkipWazuhInstall`.
- `scripts/generate-windows-odj-package.sh`
  - ODJ packages now include Wazuh enrollment parameters by default.
  - Optional `--wazuh-msi-file` can bundle the MSI for endpoints without internet access.
- Runbooks updated:
  - `docs/services/wazuh-siem.md`
  - `docs/services/endpoint-management.md`
  - `docs/operations/endpoint-onboarding-vision.md`
  - `docs/reference/ansible-playbook-catalog.md`

Note: There were pre-existing dirty worktree changes around endpoint app GPO work before this session. Do not revert them unless explicitly asked.

## Commands That Worked

Recover Windows SSH via Proxmox/QEMU Guest Agent was done with local Python using Proxmox API. It wrote only public keys to Windows and did not print token secrets.

Validation commands:

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible windows_management:windows_endpoint_pilot -i inventory/hosts -e ansible_become=false -m ansible.windows.win_ping
ansible-playbook -i inventory/hosts playbooks/endpoint-onboarding.yml
ansible wazuh_server -i inventory/hosts -b -m command -a '/var/ossec/bin/agent_control -l'
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags wazuh --vault-password-file .vault_pass
```

## Next Planned Work: Kali Purple-Team Validation

User wants to install Kali Linux later and test attacks against `ODJ-VERIFY01`. IT Manager framing should be a scoped purple-team lab, not uncontrolled hacking.

Recommended scope:

- Kali VM name: `kali01`
- Initial target only: `ODJ-VERIFY01` / `192.168.0.77`
- Do not scan or attack the whole `/24` until explicit approval.
- Do not target DCs, Keycloak, Nextcloud, mail, or storage without separate approval.
- Take snapshots before testing:
  - `odj-test01` / `ODJ-VERIFY01`
  - `kali01` after base install
- Use test accounts only. Do not use real administrator credentials for attack tests.
- Record test window, commands, Wazuh alert evidence, and gaps.

Good first validation scenarios:

1. Kali to `ODJ-VERIFY01` TCP port scan.
2. Failed login burst against exposed services, if any.
3. Windows Security Event ID `4625` ingestion in Wazuh.
4. Successful login Event ID `4624` ingestion with a test account.
5. PowerShell execution logging visibility.
6. Defender/Security event ingestion.
7. Wazuh alert/rule gaps documented and converted into follow-up rules.

Before running stronger scenarios, add or evaluate:

- Sysmon deployment on Windows endpoints.
- Wazuh rules/decoders for Windows endpoint signals.
- A written test plan with stop conditions and rollback.

## Important Operational Notes

- Wazuh manager ports `1514` and `1515` are reachable from the Windows endpoints.
- Windows endpoint SSH/WinRM/SMB state at time of repair:
  - SSH `22`: reachable
  - SMB `445`, WinRM `5985/5986`, RDP `3389`: timed out from automation01
- QEMU Guest Agent is a viable break-glass management path when Windows SSH breaks.
- For Windows OpenSSH admin users, key auth depends on:
  - `C:\ProgramData\ssh\administrators_authorized_keys`
  - ACL allowing `Administrators:F` and `SYSTEM:F`
- Wazuh Windows enrollment requires the manager-side agent group to exist before endpoints request registration.

## Current Git Status Caveat

At handoff time, worktree is dirty. Relevant new files from this work include:

- `ansible/playbooks/wazuh-agent-windows.yml`
- `ansible/playbooks/endpoint-onboarding.yml`
- `docs/archive/session-handoffs/session-handoff-2026-07-13-wazuh-windows-endpoint-kali-plan.md`

Also modified as part of this work:

- `ansible/group_vars/wazuh-rbac-vault.yml`
- `ansible/inventory/hosts`
- `ansible/playbooks/verify-all.yml`
- `ansible/playbooks/wazuh-agent-deploy.yml`
- `ansible/playbooks/wazuh-agent-logs.yml`
- `docs/operations/endpoint-onboarding-vision.md`
- `docs/reference/ansible-playbook-catalog.md`
- `docs/services/endpoint-management.md`
- `docs/services/wazuh-siem.md`
- `endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1`
- `scripts/generate-windows-odj-package.sh`

Pre-existing endpoint app GPO changes may also be present; avoid mixing them unintentionally in commits.
