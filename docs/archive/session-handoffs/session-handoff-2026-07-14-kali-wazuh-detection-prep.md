# Session Handoff - 2026-07-14 Kali Wazuh Detection Prep

Repo: `/home/sysadmin/homelab-infra`

This handoff records the follow-up after reading `session-handoff-2026-07-13-wazuh-windows-endpoint-kali-plan.md` and recent operations DB verification logs. No secrets were added.

## Context Read

- Last handoff confirmed Windows Wazuh agents are active for `ODJ-VERIFY01` and `WIN-MGMT01`.
- Recent operations DB entries showed endpoint app GPO work remains dirty in the worktree; those changes were not reverted or edited intentionally.
- User wants to personally install Kali Linux later and use it for scoped purple-team validation while improving Wazuh log understanding and possibly Telegram alerting.

## Changes Made

- Added Windows Wazuh custom detection rules:
  - `100501`: Windows Security Event ID `4625` failed logon
  - `100502`: repeated Windows failed logons from same source within 120 seconds
  - `100503`: Windows Security Event ID `4624` successful logon
  - `100504`: PowerShell Event ID `4104` script block logging
  - `100505`: Microsoft Defender Event ID `1116` malware detection
- Added redacted Windows fixture logs for those events under `ansible/files/wazuh/fixtures/`.
- Updated `ansible/files/wazuh/test-detections.sh` to validate the new Windows rules.
- Added `.gitignore` exception for `ansible/files/wazuh/fixtures/*.log` because repo-wide `*.log` ignored fixture assets.
- Added `docs/operations/kali-purple-team-validation.md` with scope, stop conditions, evidence capture, and Telegram notification boundary.
- Updated Wazuh runbooks:
  - `docs/services/wazuh-custom-detections.md`
  - `docs/services/wazuh-siem.md`
  - `docs/services/wazuh-hardening-ai-defense.md`

## Verification

- `bash -n ansible/files/wazuh/test-detections.sh`: passed
- XML/JSON local validation for `sme_rules.xml` and new Windows fixtures: passed
- Ansible MCP validate for `playbooks/wazuh-custom-detections.yml`: valid
- `git diff --check`: passed
- `scripts/check-no-secrets.sh`: passed
- Operations DB record: id `39`, scope `wazuh_windows_kali_detection_prep`, status `success`

## Not Applied

The live Wazuh manager was not changed. `playbooks/wazuh-custom-detections.yml` was not run because it can update manager rules and restart `wazuh-manager`; this should be done only after explicit approval.

## Recommended Next Steps

1. Review the new Windows fixture rules locally.
2. If approved, run:

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/wazuh-custom-detections.yml
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags wazuh --vault-password-file .vault_pass
```

3. Before Kali testing, snapshot `ODJ-VERIFY01` and the future `kali01` VM.
4. Keep initial testing limited to `ODJ-VERIFY01` / `192.168.0.77`.
5. Telegram notification implementation should wait until bot token storage, chat ID storage, rate limit, and rollback are defined. Store tokens only in vault or environment variables, not in Git.

## Worktree Caveat

Existing endpoint app GPO changes are still present and should not be mixed unintentionally with this Wazuh/Kali detection prep if committing.


## 2026-07-14 Follow-up Fix

The first live Wazuh rule deployment failed because rule `100503` used the camelCase dynamic field condition `win.eventdata.logonType`. Wazuh reported `Syntax error on tag 'win.eventdata.logonType' in rule 100503`.

Fix applied:

- Removed the `win.eventdata.logonType` field constraint from rule `100503`.
- Removed the `win.system.providerName` constraint from rule `100505` to avoid the same parser class of issue.
- Kept detection on Windows Event IDs `4624` and `1116` respectively.
- Re-ran `playbooks/wazuh-custom-detections.yml`; fixture tests passed and `wazuh-manager` restarted successfully.
- Re-ran `playbooks/verify-all.yml --tags wazuh --vault-password-file ansible/.vault_pass`; all Wazuh checks passed.

Next refinement should use real Windows alert samples from Wazuh before reintroducing more specific field constraints.
