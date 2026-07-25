# Session Handoff - 2026-07-21 Wazuh Telegram Notification Prep

Repo: `/home/sysadmin/homelab-infra`

This handoff records the follow-up after reading the latest Wazuh/Kali handoff and recent operations DB logs. No secrets were added.

## Context Read

- Latest handoff before this work: `session-handoff-2026-07-14-kali-wazuh-detection-prep.md`.
- Recent ops DB showed post-power-outage recovery completed on 2026-07-20 with full `verify-all` success and Windows endpoint Wazuh agents active.
- The 2026-07-14 handoff was stale: it said Wazuh custom detection changes were not applied, but follow-up work had deployed the fixed rules and `verify-all --tags wazuh` passed.

## Fix History Captured

The first Windows rule deployment failed because rule `100503` used `win.eventdata.logonType`, which Wazuh rejected with a rule parser syntax error. The local rule now avoids that dynamic field constraint and detects successful logon on Event ID `4624`. Rule `100505` also avoids the providerName field constraint and detects Defender Event ID `1116`.

## Changes Made This Session

- Extended `ansible/files/wazuh/ai-shadow/wazuh_ai_shadow.py`:
  - Adds a SQLite `notifications` table.
  - Queues High/Critical notification candidates while keeping enrichment `notification=false` and `automated_action=false`.
  - Adds report fields for notification pending/sent/error/dry-run/config-missing counts.
  - Adds optional one-shot Telegram delivery path using `sendMessage`.
  - Reads `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` from CLI args, environment variables, or `/etc/wazuh-ai-shadow/telegram.env`.
- Extended `test_wazuh_ai_shadow.py` with notification queue, missing config, and dry-run coverage.
- Added opt-in systemd units:
  - `ansible/files/wazuh/ai-shadow/wazuh-ai-telegram-notifier.service`
  - `ansible/files/wazuh/ai-shadow/wazuh-ai-telegram-notifier.timer`
- Updated `ansible/playbooks/wazuh-ai-shadow.yml`:
  - Creates `/etc/wazuh-ai-shadow` root/wazuh `0750` for runtime secret file placement.
  - Installs notifier units.
  - Keeps `wazuh_ai_telegram_enabled: false` by default.
  - Verifies the timer remains disabled unless explicitly enabled.
- Updated docs:
  - `docs/services/wazuh-hardening-ai-defense.md`
  - `docs/services/wazuh-siem.md`
  - `docs/services/wazuh-custom-detections.md`
  - `docs/archive/session-handoffs/session-handoff-2026-07-14-kali-wazuh-detection-prep.md`

## Verification

- `python3 -m py_compile ansible/files/wazuh/ai-shadow/wazuh_ai_shadow.py ansible/files/wazuh/ai-shadow/test_wazuh_ai_shadow.py`: passed
- `python3 ansible/files/wazuh/ai-shadow/test_wazuh_ai_shadow.py -v`: 4 tests passed
- Ansible MCP validate: `playbooks/wazuh-ai-shadow.yml` valid
- `ansible-playbook -i ansible/inventory/hosts ansible/playbooks/wazuh-ai-shadow.yml --check --diff`: passed
- `scripts/check-no-secrets.sh`: passed
- `git diff --check`: passed
- Operations DB record: id `43`, scope `wazuh_ai_shadow_telegram_notification_prep`, status `success`

## Not Applied

The updated `wazuh-ai-shadow.yml` was not applied live. Applying it would install/update files on the Wazuh host and restart the shadow collector. Telegram delivery also remains disabled by default and requires `wazuh_ai_telegram_enabled=true` plus approved runtime secret placement.

## Next Safe Apply

With explicit approval:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/wazuh-ai-shadow.yml
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-all.yml --tags wazuh --vault-password-file ansible/.vault_pass
```

Telegram enablement should be a separate approval after token storage, recipient chat, rate limit, and rollback are confirmed:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/wazuh-ai-shadow.yml   -e wazuh_ai_telegram_enabled=true
```

Do not commit `/etc/wazuh-ai-shadow/telegram.env`, bot tokens, chat IDs, webhook URLs, or alert full logs.

## Worktree Caveat

Pre-existing endpoint app GPO changes and fixture `.log` tracking cleanup are still mixed in the worktree. Keep commits separated by topic if committing.


## 2026-07-21 Live Apply

After explicit approval, the opt-in Telegram notification queue support was applied to the Wazuh host.

Applied command:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/wazuh-ai-shadow.yml
```

Result:

- Playbook passed: `ok=14 changed=5 failed=0` on `wazuh`.
- `/etc/wazuh-ai-shadow` was created with root/wazuh ownership for future runtime secret placement.
- Updated `wazuh_ai_shadow.py` and target-side unit tests were installed.
- `wazuh-ai-telegram-notifier.service` and `wazuh-ai-telegram-notifier.timer` were installed.
- `wazuh-ai-shadow.service` was restarted and verified active.
- `wazuh-ai-telegram-notifier.timer` remains disabled by default.
- No Telegram bot token or chat ID was configured.

Verification command:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-all.yml --tags wazuh --vault-password-file ansible/.vault_pass
```

Result: passed for Wazuh manager, Windows Wazuh agents, custom detections, RBAC, snapshots, and AI shadow safety checks.

Metrics snapshot after apply:

- `events_total=10000`
- `events_pending=0`
- `events_enriched=10000`
- `notification_pending=0`
- `notification_sent=0`
- `notification_error=0`
- `redaction_leak_count=0`
- `invalid_json_total=447`
- `trimmed_total=37942`

The invalid JSON and trimmed counters are cumulative collector metrics from the existing spool lifecycle, not an apply failure.

Operations DB record: id `44`, scope `wazuh_ai_shadow_telegram_notification_apply`, status `success`.


## 2026-07-22 Telegram Enable Attempt Blocked

The user approved continuing to Telegram enablement. The enablement was not completed because runtime secrets were not present.

Observed state:

- `/etc/wazuh-ai-shadow/telegram.env` does not exist on the Wazuh host.
- Controller environment variables `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` are missing.
- `wazuh-ai-telegram-notifier.timer` remains disabled.

Safety improvement added:

- `wazuh-ai-shadow.yml` can now create `/etc/wazuh-ai-shadow/telegram.env` from controller environment variables without logging values.
- If `wazuh_ai_telegram_enabled=true` is requested, the playbook now requires the env file to exist with `root:wazuh` ownership and mode `0640` before enabling the timer.
- Secret key validation runs with `no_log: true`.

Verification:

- Ansible MCP syntax validate passed.
- `ansible-playbook -i ansible/inventory/hosts ansible/playbooks/wazuh-ai-shadow.yml --check --diff -e wazuh_ai_telegram_enabled=true` failed at the intended guard because the secret file was absent.
- Default `ansible-playbook -i ansible/inventory/hosts ansible/playbooks/wazuh-ai-shadow.yml --check --diff` passed with `changed=0 failed=0`.
- Python compile passed.
- `test_wazuh_ai_shadow.py -v` passed 4 tests.
- `git diff --check` passed.
- `scripts/check-no-secrets.sh` passed.
- Operations DB record: id `45`, scope `wazuh_ai_shadow_telegram_enable_attempt`, status `blocked`.

To complete enablement later, provide runtime secrets without committing them:

```bash
export TELEGRAM_BOT_TOKEN='<runtime-secret>'
export TELEGRAM_CHAT_ID='<approved-chat-id>'
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/wazuh-ai-shadow.yml   -e wazuh_ai_telegram_enabled=true
```

Or create `/etc/wazuh-ai-shadow/telegram.env` on the Wazuh host with `root:wazuh` and mode `0640`, then rerun the same playbook with `wazuh_ai_telegram_enabled=true`.
