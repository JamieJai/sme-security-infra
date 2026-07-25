# Session Handoff: Kali VM Installation Complete

Date: 2026-07-25

## Completed

- Read the prior Kali/Wazuh handoff context and `docs/operations/kali-purple-team-validation.md`.
- Verified Wazuh preflight and Windows endpoint Ansible reachability.
- Created target snapshot `pre-kali-purple-20260725` for `ODJ-VERIFY01` / VMID `110`.
- Downloaded and SHA256-verified the official Kali `2026.2` installer ISO, then uploaded it to Proxmox `local` ISO storage.
- Added `scripts/proxmox_iso_storage.py` for repeatable ISO storage operations.
- Added `scripts/proxmox_vnc_console.py` for short-lived-ticket Proxmox console screenshots and keyboard input. Shifted punctuation is mapped explicitly, and `type-file` avoids placing secret text in command arguments.
- Added Terraform `modules/kali-vm`, `kali_vms` wiring, and post-install flags.
- Installed Kali GNU/Linux Rolling from the `2026.2` ISO on `kali01`, then upgraded it to rolling release `2026.3`:
  - VMID: `111`
  - Node: `pve01`
  - CPU/RAM/Disk: 2 cores, 4096 MiB, 40G
  - Host/domain: `kali01.toss.lan`
  - Desktop/toolset: Xfce, top10, kali-linux-default
  - Network: DHCP `192.168.0.37/24` on `vmbr0`
- Configured the official `kali-rolling` APT source in `/etc/apt/sources.list.d/kali.sources`.
- Installed and enabled OpenSSH and QEMU Guest Agent.
- Registered the controller SSH public key for `kaliadmin`, verified non-interactive key login, and disabled password and keyboard-interactive SSH authentication.
- Detached the installer ISO and set boot order to `scsi0`.
- Enabled Proxmox QEMU Guest Agent and verified Agent API ping.
- Updated the Kali Terraform module for installation and post-install states:
  - `installer_attached`
  - `qemu_agent_enabled`
  - `automatic_reboot = false`
  - `skip_ipv6 = true`
- Created and verified snapshot `post-install-20260725` for `kali01`.
- Upgraded 790 packages from the signed rolling repository, verified zero pending updates and package integrity, and booted kernel `7.0.12+kali-amd64`.
- Created and verified updated baseline snapshot `post-update-20260725`.
- Rebooted after snapshot and verified SSH, IP, and Guest Agent recovery.
- Added `scripts/kali-purple-team-scan.sh`, which rejects all targets except `ODJ-VERIFY01` / `192.168.0.77` and requires `PURPLE_TEAM_ACK` for execution.
- Telegram notification enablement remains complete; direct delivery, queued alerts, and the recurring notifier timer were previously verified.

## Verification

- Kali SSH key login: passed.
- SSH service: `enabled`, `active`.
- SSH hardening: `PasswordAuthentication no`, `KbdInteractiveAuthentication no`.
- QEMU Guest Agent service: `active`.
- Proxmox Agent API ping: passed.
- Proxmox config: `agent=1`, `ide2=none,media=cdrom`, `boot=order=scsi0`.
- Snapshots `post-install-20260725` and `post-update-20260725`: present.
- Post-update snapshot boot: passed; `eth0` returned as `192.168.0.37/24`, kernel `7.0.12+kali-amd64`, pending updates `0`.
- `terraform fmt -recursive`: passed.
- `terraform validate`: passed.
- `terraform plan -target='module.kali_vm["kali01"]' -detailed-exitcode`: `No changes`.
- `scripts/proxmox_vnc_console.py` bytecode compilation: passed.
- Scope wrapper dry run: passed.
- Wrong target and missing acknowledgement guards: rejected as expected.

## Notes

- Full Terraform plan previously showed unrelated existing drift on `win-mgmt01` (`machine = "pc-q35-10.1" -> "q35"`). It was not applied.
- Telmate Proxmox provider `3.0.2-rc04` returned `VM 111 already running` after the first agent update. The agent change had applied. The module now disables provider-managed automatic reboot, the VM was rebooted explicitly, and the final targeted plan converges with no changes.
- The installer had no network APT source because installation initially ran offline. The official Kali deb822 source was added and `apt-get update` downloaded the signed rolling indexes successfully.
- Proxmox NIC firewall is enabled, but VM firewall rules are still empty and cluster/node firewall options are not explicitly set. Do not run validation traffic until egress is constrained to the approved target or the VM is moved to an isolated lab VLAN.
- No live scan or attack traffic was generated in this session.
- Runtime credentials, initial passwords, Terraform secrets, Telegram token, and VNC tickets are not stored in Git.

## Next

1. Add and verify egress containment for `kali01`, allowing only the approved target and required management/package paths, or move it to a dedicated lab VLAN.
2. Recheck that the `ODJ-VERIFY01` Wazuh agent is Active and the custom detection fixture tests pass.
3. Record the lab account and test window.
4. Review the scope wrapper dry run, then run the first approved scan against `192.168.0.77` only.
5. Capture Wazuh evidence for rules `100501` through `100505` and confirm Telegram delivery for eligible alerts.
