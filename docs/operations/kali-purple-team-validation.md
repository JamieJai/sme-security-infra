# Kali Purple-Team Validation Runbook

이 문서는 개인 Kali VM을 homelab 보안 검증에 사용할 때의 운영 범위와 증거 수집 기준이다. 목적은 무차별 침투가 아니라 Windows endpoint와 Wazuh 탐지 품질을 안전하게 확인하는 purple-team lab이다.

## Scope

초기 범위는 다음으로 제한한다.

| 항목 | 기준 |
|---|---|
| Attacker VM | `kali01` / `192.168.0.37` |
| Initial target | `ODJ-VERIFY01` / `192.168.0.77` |
| SIEM | `wazuh` / `192.168.0.30` |
| Test account | 별도 lab 계정만 사용 |
| Excluded targets | DC, Keycloak, Nextcloud, mail, storage, 전체 `/24` scan |

전체 `/24` scan, domain controller 대상 테스트, credential attack, exploit framework 사용은 별도 승인 전까지 하지 않는다.

## Preconditions

1. `ODJ-VERIFY01` snapshot을 생성한다.
2. `kali01` base install 후 snapshot을 생성한다.
3. Wazuh manager에서 `ODJ-VERIFY01` agent가 Active인지 확인한다.
4. `playbooks/wazuh-custom-detections.yml`가 fixture test를 통과한 상태인지 확인한다.
5. 테스트 시작 시각, 종료 예정 시각, 담당자, target IP를 기록한다.
6. `kali01`의 egress가 승인 대상 밖으로 나가지 않도록 guest nftables guard, Proxmox firewall 또는 별도 lab VLAN으로 통제한다.

## Initial Scenarios

1. `kali01`에서 `ODJ-VERIFY01`만 대상으로 TCP port scan을 수행한다.
2. 발견된 서비스가 SSH 등 승인된 lab service일 때만 실패 로그인 burst를 수행한다.
3. Windows Security Event ID `4625` failed logon이 Wazuh alert rule `100501` 또는 burst rule `100502`로 보이는지 확인한다.
4. lab 계정으로 성공 로그인을 수행하고 Event ID `4624`가 rule `100503`으로 보이는지 확인한다.
5. `ODJ-VERIFY01`에서 승인된 PowerShell 명령을 실행하고 Event ID `4104`가 built-in `918xx` rule과 `windows_eventchannel` decoder로 보이는지 확인한다.
6. Defender test는 EICAR 같은 안전한 test artifact만 사용하고, Event ID `1116`이 rule `100505`로 보이는지 확인한다.

## Stop Conditions

다음 조건이 하나라도 발생하면 테스트를 중단한다.

- target이 `192.168.0.77` 밖으로 확대됐다.
- DC, identity, mail, storage, Nextcloud로 트래픽이 향했다.
- 계정 잠금, 서비스 장애, Wazuh agent disconnect가 발생했다.
- 의도하지 않은 credential, token, private data가 터미널 또는 로그에 노출됐다.
- 테스트 명령이 재현 가능하게 기록되지 않았다.

## Evidence To Capture

테스트별로 다음을 남긴다.

- 테스트 window와 command summary
- target host, source host, source IP
- Wazuh agent ID와 alert rule ID
- `alerts.json` 또는 Dashboard에서 확인한 alert timestamp
- 탐지되지 않은 경우 raw Windows Event ID와 Wazuh ingestion 여부
- false positive 또는 rule tuning 필요사항

민감한 원본 로그, password, token, cookie, mail body, 실제 사용자명은 문서에 저장하지 않는다. fixture로 남길 때는 `ansible/files/wazuh/fixtures`의 redaction 기준을 따른다.

## 2026-07-25 Installation Status

완료된 준비 상태:

- Wazuh preflight: `verify-all.yml --tags wazuh --vault-password-file ansible/.vault_pass` 통과.
- Windows endpoint reachability: `win-mgmt01`, `odj-verify01` Ansible `win_ping` 통과.
- Target snapshot: `ODJ-VERIFY01` / VMID `110` snapshot `pre-kali-purple-20260725` 생성 및 API 검증 완료.
- Kali installer ISO: 공식 `current` archive에서 `kali-linux-2026.2-installer-amd64.iso` 다운로드 및 `SHA256SUMS` 검증 완료.
- Proxmox `local` ISO storage: `local:iso/kali-linux-2026.2-installer-amd64.iso` 업로드 완료.
- Kali OS: Kali GNU/Linux Rolling `2026.2` 설치 후 공식 rolling 저장소 기준 `2026.3`으로 전체 업데이트 완료; Xfce, top10, default toolset 포함.
- Identity: hostname `kali01`, domain `toss.lan`, admin account `kaliadmin`.
- Network: `eth0` DHCP `192.168.0.37/24`, `vmbr0`, Proxmox NIC firewall flag enabled.
- Remote access: OpenSSH enabled, controller public-key login verified, password and keyboard-interactive SSH disabled.
- Guest integration: `qemu-guest-agent` enabled and active; Proxmox Agent ping passed.
- Boot state: installer ISO detached, boot order `scsi0`, Proxmox `agent=1`.
- Kali snapshots: 설치 직후 `post-install-20260725`, 전체 업데이트 후 `post-update-20260725` 생성 및 API 검증 완료.
- Update state: 790 packages upgraded, remaining updates `0`, running kernel `7.0.12+kali-amd64`, `apt-get check` and `dpkg --audit` passed.
- Terraform: post-install flags are `installer_attached = false`, `qemu_agent_enabled = true`; targeted plan reports `No changes`.
- Operations DB: `kali01` VM asset and installation verification recorded.
- Validation traffic: `2026-07-28` initial single-target port baseline 완료.

`2026-07-25` controller preflight 제한 포트 baseline:

| Port | Result |
|---:|---|
| 22/tcp | reachable |
| 445/tcp | timeout |
| 3389/tcp | timeout |
| 5985/tcp | timeout |
| 5986/tcp | timeout |

현재 남은 detection validation 작업:

1. 별도 lab 계정과 lockout-safe test window를 기록한다.
2. Kali source 전용 target firewall rule이 필요한지 검토하고 별도 승인한다.
3. `ODJ-VERIFY01` Wazuh agent가 Active인지 각 테스트 직전에 다시 확인한다.
4. 인증, PowerShell, Defender 시나리오는 각각 범위와 rollback을 확인한 뒤 실행한다.

Kali를 먼저 설치하는 목적은 공격 도구 확보 자체가 아니다. Wazuh 수집, 탐지 규칙, Telegram 알림, 대상 snapshot, scope guard를 먼저 준비한 뒤 통제된 이벤트를 발생시켜 탐지 품질을 검증하기 위한 트래픽 발생기다.

## Scope-Enforced Initial Scan

초기 포트 baseline은 대상 제한 wrapper를 사용한다. 기본 실행은 dry run이며 CIDR, hostname, 다른 IP, NSE script, service detection을 받지 않는다.

```bash
./scripts/kali-purple-team-scan.sh --target 192.168.0.77

PURPLE_TEAM_ACK=ODJ-VERIFY01:192.168.0.77 \
  ./scripts/kali-purple-team-scan.sh --target 192.168.0.77 --execute
```

실행 결과는 기본적으로 Git에서 제외되는 `artifacts/kali-validation/`에 저장한다. 이 wrapper는 운영 실수를 줄이는 보조 통제이며 VLAN 또는 Proxmox firewall 격리를 대체하지 않는다.

## Guest Egress Guard

Proxmox cluster/node firewall은 현재 활성화되지 않았으며 `kali01` VM firewall rule도 비어 있다. NIC의 `firewall=1` 플래그만으로는 패킷이 제한되지 않는다. 클러스터 전체 firewall 상태를 바꾸지 않고 `kali01` 한 대만 격리하기 위해 guest nftables guard를 사용한다.

`scripts/kali_egress_guard.py`는 Proxmox QEMU Guest Agent를 통해 root 권한으로 고정된 ruleset만 관리한다. node `pve01`, VMID `111`, guest IP `192.168.0.37`, target `192.168.0.77`은 코드에 고정되어 있고 임의 target/CIDR/port argument를 받지 않는다.

허용 범위:

- loopback
- established/related 응답 트래픽
- `192.168.0.77` ICMP
- `192.168.0.77` TCP `22,445,3389,5985,5986`
- DHCP renewal용 UDP `68 -> 67` to `192.168.0.1` 또는 broadcast
- inbound accept
- forwarding과 그 밖의 outbound traffic drop

계획과 guest-side 문법 검증:

```bash
scripts/kali_egress_guard.py apply
scripts/kali_egress_guard.py check
scripts/kali_egress_guard.py status
scripts/kali_egress_guard.py verify
```

`apply`는 기본적으로 ruleset만 출력하며 변경하지 않는다. 실제 적용은 정확한 acknowledgement와 `--execute`가 모두 필요하다.

```bash
KALI_EGRESS_ACK=kali01:111:192.168.0.77 \
  scripts/kali_egress_guard.py apply --execute
```

적용 후 확인:

```bash
scripts/kali_egress_guard.py status
ssh -o BatchMode=yes kaliadmin@192.168.0.37 true
```

guard가 활성화된 동안 외부 DNS, APT repository, NTP를 포함한 승인 대상 이외의 outbound 통신은 차단된다. Kali package update가 필요하면 검증 window를 종료하고 먼저 rollback한다.

```bash
KALI_EGRESS_ACK=kali01:111:192.168.0.77 \
  scripts/kali_egress_guard.py rollback --execute
```

rollback은 첫 적용 전에 저장한 `/etc/nftables.conf`를 복원하고 nftables 서비스를 disable한 뒤 runtime ruleset을 비운다. QEMU Guest Agent는 네트워크 경로와 무관하므로 잘못된 firewall 적용 뒤에도 rollback 경로로 사용할 수 있다.

## Telegram Notification Boundary

Telegram 알림은 High/Critical analyst notification 용도로만 사용한다. Bot token, chat ID, webhook URL은 repo에 저장하지 않고 vault 또는 environment variable로만 전달한다. 자동 차단, 자동 격리, 계정 잠금 같은 대응은 이 단계의 범위가 아니다.

초기 권장 기준:

- rule `100502` Windows failed logon burst
- rule `100505` Defender malware detection
- Wazuh agent disconnect가 일정 시간 이상 지속되는 경우

2026-07-25에 Telegram notifier를 활성화했고 direct delivery, queued alert 7건, 1분 주기 반복 실행을 검증했다. Runtime secret은 Wazuh host의 권한 제한 파일에만 있으며 Git에는 저장하지 않는다.

## 2026-07-28 Egress Preparation Status

- Wazuh `verify-all.yml --tags wazuh` 통과
- `win-mgmt01`, `odj-verify01` `win_ping` 통과
- Wazuh managed agent 전체 Active
- `kali01` SSH, QEMU Guest Agent, IP `192.168.0.37/24` 확인
- Proxmox cluster/node firewall options unset
- `kali01` NIC `firewall=1`, VM firewall options unset, VM rules `0`
- guest nftables service disabled/inactive, runtime ruleset empty
- `kali_egress_guard.py` 단위 테스트와 guest-side nftables syntax check 통과
- 실제 egress guard 적용 완료:
  - nftables service enabled/active
  - 저장된 config hash와 runtime table 검증 통과
  - service restart 후 정책 지속성과 SSH 연결 유지 확인
  - target ICMP/TCP는 allow counter에 기록
  - 비대상 내부 host와 인터넷 시도는 drop counter에 기록
- `ODJ-VERIFY01` SSH는 기존 Windows Firewall rule이 `automation01` / `192.168.0.40`만 허용하므로 Kali 연결은 대상 host에서 거부됨
- live scan은 아래 baseline 결과로 완료

## 2026-07-28 Initial Port Baseline

Test window:

- Start: `2026-07-28 15:20:56 KST` / `2026-07-28T06:20:56Z`
- End: `2026-07-28 15:20:59 KST`
- Source: `kali01` / `192.168.0.37`
- Target: `ODJ-VERIFY01` / `192.168.0.77`
- Method: TCP connect scan, no DNS, no service/version detection, no NSE

Command scope:

```text
nmap -Pn -sT -n --max-retries 2 --host-timeout 2m \
  -p 22,445,3389,5985,5986 192.168.0.77
```

Result:

| Port | State |
|---:|---|
| 22/tcp | filtered |
| 445/tcp | filtered |
| 3389/tcp | filtered |
| 5985/tcp | filtered |
| 5986/tcp | filtered |

The target was up and the scan completed in `3.03` seconds. Kali nftables
recorded ten target TCP packets in the fixed target allow rule. The target
Windows Firewall then filtered them. Its existing `OpenSSH Server from
automation01` rule only permits `192.168.0.40`; no target firewall rule was
changed.

Evidence:

- Local path: `artifacts/kali-validation/`
- Base name: `20260728T062056Z-odj-verify01-initial-ports`
- `.nmap`: `d5ee66e42c0bd232668887e2065aab4a3043c834d0758a81ab380cbf5299f2f0`
- `.gnmap`: `793f2231f15762152f762eb849684f43650f8d1c0f9433060d8232e0d1cba224`
- `.xml`: `f0e1365f9b18fd6865bae4b9a2c4e2f4b0bead60a31e5daf47a3e70ccdd8d667`

Detection outcome:

- Windows Security Event `5152/5157`: no events in the scan window.
- Wazuh alerts for `ODJ-VERIFY01` after scan start: `0`.
- Rules `100501-100505`: not triggered, as expected for a filtered port
  baseline without authentication, PowerShell, or Defender activity.
- Wazuh agent `008` remained Active.
- Telegram notifier remained enabled/active with `pending=0`, `error=0`,
  `sent=7`; no notification was expected for this baseline.
- Kali egress guard live verification passed after the scan.

The next detection step requires a separately approved Kali-scoped target
firewall rule and a dedicated lab account or a local endpoint event. Do not
broaden the existing automation-only SSH rule.

Post-baseline rule review found that the original Windows custom rules were
constrained to the fixture `json` decoder while live agent events use
`windows_eventchannel`. The applied correction adds JSON fixture parent
`100500`, attaches live rules to built-in EventChannel parents, pins
provider/channel/event ID fields, and limits success rule `100503` to
interactive/RDP logon type `2` or `10`. A type `3` negative fixture prevents
ordinary SSH/network logons from being mislabeled as interactive. Live rule
`100501` was verified with one nonexistent local identity probe; type `3`
network logons did not produce `100503`.

Central PowerShell and Defender EventChannel collection was applied to the
`windows` group and synchronized to both Windows agents. A timestamp backup
created inside the shared directory initially caused Windows unmerge error 123;
the backup was preserved under `/var/backups/wazuh-windows-agent-conf/`, the
shared directory was cleaned, and both agents converged on shared hash
`b6c7407ae6e1986b42b592db2a3dd69a`.

The first received PowerShell 4104 probe matched built-in rule `91816`, proving
collection. Follow-up marker probes showed that Script Block Logging policy is
not configured, so simple benign script blocks are not recorded even though
PowerShell's automatic suspicious-content logging still produces selected 4104
events. Custom rule `100504` is therefore restricted to JSON
fixture/integration validation and is not attached to the live rule tree. Live
PowerShell severity remains owned by built-in `918xx` rules. The Windows
playbook now has an explicit `observe`/`enabled`/`disabled` policy switch, with
`observe` as the non-changing default. Defender rule `100505` follows built-in
1116 rule `62123` and preserves level 12. No Defender test artifact has been
created.

Final Wazuh verification after rule tuning:

- Custom detection repeat apply: `changed=0`, failed `0`.
- `verify-all.yml --tags wazuh`: passed for manager and both Windows endpoints.
- `wazuh-remoted` and `wazuh-analysisd`: running; TCP 1514 listening.
- All eight managed agents: Active.
- Recent endpoint 4104 events: built-in rules `91816`/`91837`, level 4,
  decoder `windows_eventchannel`.
- Script Block Logging policy: absent on `ODJ-VERIFY01` and `WIN-MGMT01`.
- Telegram notifier: enabled/active, `sent=7`, no pending or error rows.
- Kali egress guard: live verification passed.
