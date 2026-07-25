# Session Handoff: Wazuh Telegram Enabled

Date: 2026-07-25

## Completed

- Confirmed the Telegram bot with Bot API `getMe`.
- Derived the approved private recipient from the most recent private
  `getUpdates` event after the user sent `/start`.
- Installed the runtime secret file on the Wazuh host as
  `/etc/wazuh-ai-shadow/telegram.env` with `root:wazuh` ownership and mode
  `0640`. Secret values were not written to Git or documentation.
- Enabled `wazuh-ai-telegram-notifier.timer`.
- Sent a direct delivery test successfully.
- Delivered seven queued High/Critical Wazuh notification candidates.

## Timer Recovery Fix

The timer initially remained `active (elapsed)` with no next run after the host
clock had advanced from July 22 to July 25. Restarting the timer did not create
a new schedule because both monotonic timer deadlines were already in the past.

`ansible/playbooks/wazuh-ai-shadow.yml` now:

- reads `NextElapseUSecMonotonic`;
- starts the one-shot notifier service only when the enabled timer has no next
  run, which establishes a fresh `OnUnitActiveSec` reference;
- fails verification if an enabled timer still has no next run.

## Verification

- Telegram Bot API direct `sendMessage`: passed.
- Enablement apply: `ok=20 changed=1 failed=0`.
- Repeat apply: `ok=19 changed=0 failed=0`.
- Runtime secret permissions: `root:wazuh 0640`.
- Notification database status after delivery: `sent=7`.
- Automatic follow-up run completed at `2026-07-25 15:40:03 KST` and systemd
  scheduled the next run.
- `verify-all.yml --tags wazuh`: passed for the Wazuh manager, Windows agents,
  custom detections, API, retention, snapshots, RBAC, and AI shadow safety.
- Local Python compile and four unit tests: passed.

## Security Note

The token was pasted into the conversation. It is active now because the user
explicitly requested immediate enablement, but it should be rotated in BotFather
and replaced in the same runtime-only file. Do not commit bot tokens, chat IDs,
webhook URLs, or alert full logs.
