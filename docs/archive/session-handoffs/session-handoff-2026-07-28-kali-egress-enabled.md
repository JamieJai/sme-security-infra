# Session Handoff: Kali Egress Guard Enabled

Date: 2026-07-28

## Completed

- Confirmed Git `main` matched `origin/main` before starting.
- Read the latest Kali installation handoff and purple-team validation runbook.
- Read recent operations DB results. The remaining gate was still Kali egress containment.
- Re-ran Wazuh verification:
  - `verify-all.yml --tags wazuh` passed.
  - `win-mgmt01` and `odj-verify01` were reachable.
  - Both Windows Wazuh services were running.
  - Every managed Wazuh agent was Active.
- Re-verified `kali01`:
  - SSH key login passed.
  - Kernel `7.0.12+kali-amd64`.
  - SSH and QEMU Guest Agent active.
  - `eth0` remained `192.168.0.37/24`.
- Queried Proxmox firewall state through the local runtime API credentials without printing secrets:
  - cluster firewall options unset;
  - `pve01` firewall options unset;
  - `kali01` NIC has `firewall=1`;
  - VM firewall options unset;
  - VM firewall rules empty.
- Verified QEMU Guest Agent arbitrary exec works as root for VMID `111`.
- Verified guest nftables is installed but disabled/inactive and the runtime ruleset is empty.

## Added

- `scripts/kali_egress_guard.py`
  - Fixed to `pve01`, VMID `111`, `kali01`, and target `192.168.0.77`.
  - Does not accept arbitrary target, CIDR, or port arguments.
  - Uses QEMU Guest Agent so rollback does not depend on guest network access.
  - `apply` and `rollback` are dry-run by default.
  - Live execution requires `--execute` and
    `KALI_EGRESS_ACK=kali01:111:192.168.0.77`.
  - Preserves the original `/etc/nftables.conf` before the first apply.
- `tests/test_kali_egress_guard.py`
  - Fixed-scope ruleset assertions.
  - QGA form encoding and polling tests.
  - Exact acknowledgement guard tests.
- Updated `docs/operations/kali-purple-team-validation.md` with apply, verify,
  package update boundary, and rollback instructions.

## Verification

- Python syntax compilation passed.
- Seven unit tests passed after the live verification command and repository
  import fallback were added.
- Dry-run apply printed the expected fixed ruleset.
- Guest identity, IP, nft binary, and `nft --check --file -` passed through QGA.
- At this preparation checkpoint, no live firewall policy or validation scan
  had been applied.

## Live Apply

After explicit approval, the fixed nftables guard was applied to `kali01`.

Result:

- nftables service is enabled and active.
- `/etc/nftables.conf` matches the generated guard config.
- The pre-guard config was preserved for rollback.
- Restarting nftables reloaded the policy successfully.
- Controller SSH access to `kali01` remained available.
- DHCP address `192.168.0.37/24` and gateway `192.168.0.1` remained present.
- Target ICMP and TCP attempts incremented target allow counters.
- Non-target internal and internet attempts incremented the final drop counter.
- Wazuh tagged verification passed after the apply.

Target connectivity note:

- `ODJ-VERIFY01` listens on TCP 22.
- Its enabled inbound rule is `OpenSSH Server from automation01`.
- The rule only permits source `192.168.0.40`, so Kali traffic is rejected by
  the target firewall after passing the Kali egress allow rule.
- No target firewall rule was changed.

## Initial Port Baseline

After separate explicit approval, the fixed wrapper was streamed to `kali01`
and executed there.

Scope:

- Window: `2026-07-28 15:20:56-15:20:59 KST`
- Source: `kali01` / `192.168.0.37`
- Target: `ODJ-VERIFY01` / `192.168.0.77`
- TCP ports: `22,445,3389,5985,5986`
- No CIDR, DNS, NSE, service detection, credential attempt, or exploit

Result:

- Target up.
- All five ports reported `filtered`.
- Scan duration: `3.03` seconds.
- Kali target TCP allow counter increased by ten packets.
- Existing target Windows Firewall source restriction explains the result.

Evidence copied to ignored local path `artifacts/kali-validation/`:

- `20260728T062056Z-odj-verify01-initial-ports.nmap`
  - SHA256 `d5ee66e42c0bd232668887e2065aab4a3043c834d0758a81ab380cbf5299f2f0`
- `20260728T062056Z-odj-verify01-initial-ports.gnmap`
  - SHA256 `793f2231f15762152f762eb849684f43650f8d1c0f9433060d8232e0d1cba224`
- `20260728T062056Z-odj-verify01-initial-ports.xml`
  - SHA256 `f0e1365f9b18fd6865bae4b9a2c4e2f4b0bead60a31e5daf47a3e70ccdd8d667`

Post-scan verification:

- Windows Security packet-filter events `5152/5157`: none.
- Wazuh alerts for agent `ODJ-VERIFY01` after scan start: zero.
- Custom rules `100501-100505`: not triggered, as expected.
- Agent `008` remained Active.
- Telegram notifier timer enabled/active and scheduled.
- AI shadow notification metrics: `pending=0`, `error=0`, `sent=7`.
- Wazuh redaction leak count: zero.
- Kali egress guard verification passed.

## Detection Rule Finding

The baseline review exposed a live/fixture decoder mismatch:

- Redacted fixture JSON is decoded as `json`.
- Live Windows agent events are decoded as `windows_eventchannel`.
- Rules `100501`, `100503`, `100504`, and `100505` were constrained with
  `<decoded_as>json</decoded_as>`.
- Live 4624 events therefore matched built-in rule `60106` but not custom rule
  `100503`.

Prepared correction:

- Add level 0 parent `100500` for JSON fixture/integration events.
- Attach live rules to the applicable built-in EventChannel parent and fixture
  parent `100500`.
- Match the expected Windows provider, channel, and event ID fields.
- Limit `100503` to interactive/RDP logon type `2` or `10`.
- Add a type `3` network-logon negative fixture to prevent SSH/automation
  activity from being mislabeled as interactive.
- Preserve timestamped target-side decoder and rule backups for post-restart
  rollback in addition to the playbook's in-memory transaction rollback.

At this finding checkpoint, the corrected rule file had not yet been applied.

Live apply follow-up:

- The first decoder-independent field-only version still did not enter the live
  Wazuh rule tree.
- Added level 0 JSON parent `100500` and attached custom rules to built-in
  EventChannel parents plus `100500`.
- Re-applied transactionally; all positive and negative fixtures passed.
- A single nonexistent local identity probe generated live rule `100501` level
  7 through decoder `windows_eventchannel`.
- Network logon type `3` did not generate `100503`.
- Full Wazuh verification passed and all agents remained Active.

Collection gap:

- The endpoint generated ten PowerShell 4104 events during the first live
  probe, but Wazuh received none.
- Current Windows agent config only collects Application, Security, and System.
- Prepared central `windows` group `agent.conf` collection for PowerShell
  Operational and Microsoft Defender Operational.

Shared collection apply:

- Candidate validation and initial deployment passed.
- Ansible's default timestamp backup was created inside the shared directory.
- Wazuh included that backup in `merged.mg`; its colon-bearing filename caused
  Windows unmerge error 123 on both agents.
- Moved the backup intact to `/var/backups/wazuh-windows-agent-conf/`.
- Manager regenerated `merged.mg` without the backup entry.
- Both agents synchronized shared hash
  `b6c7407ae6e1986b42b592db2a3dd69a`; errors stopped after `16:59:59 KST`.
- Updated the playbook to store safe backups outside the shared directory and
  fail if `*~` files are present there.

PowerShell/Defender rule tuning:

- The first received 4104 probe matched built-in rule `91816`; custom `100504`
  did not match because parent `60000` was above the script-block branch.
- Three harmless marker execution methods did not put the marker in an endpoint
  4104 event. The endpoint Script Block Logging policy is not configured;
  selected PowerShell automatic logging still reaches Wazuh built-in `918xx`.
- Rule `100504` is now JSON fixture/integration-only at level 5 and is not
  attached to the live rule tree. This prevents a marker from overriding
  higher-severity built-in PowerShell detections.
- The Windows agent playbook pre-stages an explicit
  `wazuh_windows_script_block_logging_state` switch. Its default `observe`
  performs no registry change; `enabled` and rollback `disabled` require an
  explicit extra variable.
- Defender rule `100505` now follows built-in Event ID 1116 rule `62123` and
  preserves its level 12 severity.
- Defender live validation remains pre-staged only; no EICAR or other test
  artifact has been created.
- The first manager restart after this tuning hit a transient
  `wazuh-remoted` segfault. Configuration tests and agent key structure were
  valid; a foreground diagnostic start restored TCP 1514 and all eight agents.
- The custom detection playbook now flushes the restart handler and requires
  TCP 1514 plus every managed agent to return Active before reporting success.

Final verification:

- The final rule apply restarted Wazuh successfully; the remoted segfault did
  not recur.
- A repeat custom detection apply converged with `changed=0`.
- Full `verify-all.yml --tags wazuh` passed.
- `wazuh-remoted` and `wazuh-analysisd` are running, TCP 1514 is listening, and
  all eight managed agents are Active.
- Recent ODJ-VERIFY01 4104 events are visible through built-in rules
  `91816`/`91837` and decoder `windows_eventchannel`.
- Script Block Logging policy remains absent on both Windows endpoints.
- Telegram notifier remains enabled and active with `sent=7` and no pending or
  error rows.
- The live Kali egress guard verification still passes.
- Operations DB record: `id=56`, scope
  `wazuh_windows_eventchannel_collection_tuning`, status `success`.

## Next

1. Decide whether to approve PowerShell Script Block Logging policy enablement
   on the pilot endpoint before broadening benign 4104 visibility.
2. Validate live rule `100505` only after separately approving a Defender test
   artifact.
3. Decide whether a separate Kali-scoped Windows Firewall rule is warranted for
   later failed-login validation. Do not broaden the existing automation-only
   SSH rule.
4. Create a dedicated lab account with an explicit lockout-safe test procedure.
5. Run failed and successful login scenarios, then validate Wazuh rules `100501`
   through `100503`.
6. After approval, validate broader PowerShell built-in `918xx` visibility and
   the Defender custom rule `100505`.
