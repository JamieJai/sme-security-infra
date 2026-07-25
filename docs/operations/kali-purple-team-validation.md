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
6. `kali01`의 egress가 승인 대상 밖으로 나가지 않도록 Proxmox firewall 또는 별도 lab VLAN으로 통제한다.

## Initial Scenarios

1. `kali01`에서 `ODJ-VERIFY01`만 대상으로 TCP port scan을 수행한다.
2. 발견된 서비스가 SSH 등 승인된 lab service일 때만 실패 로그인 burst를 수행한다.
3. Windows Security Event ID `4625` failed logon이 Wazuh alert rule `100501` 또는 burst rule `100502`로 보이는지 확인한다.
4. lab 계정으로 성공 로그인을 수행하고 Event ID `4624`가 rule `100503`으로 보이는지 확인한다.
5. `ODJ-VERIFY01`에서 승인된 PowerShell 명령을 실행하고 Event ID `4104`가 rule `100504`로 보이는지 확인한다.
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
- Validation traffic: 아직 실행하지 않았다.

`ODJ-VERIFY01` 제한 포트 baseline:

| Port | Result |
|---:|---|
| 22/tcp | reachable |
| 445/tcp | timeout |
| 3389/tcp | timeout |
| 5985/tcp | timeout |
| 5986/tcp | timeout |

검증 시작 전 남은 작업:

1. Proxmox VM firewall rule은 아직 0개이고 cluster/node firewall option도 명시적으로 설정되어 있지 않으므로, `kali01` egress를 `192.168.0.77`의 승인 포트로 제한하거나 별도 lab VLAN에 격리한다.
2. `ODJ-VERIFY01` Wazuh agent가 Active인지 테스트 직전에 다시 확인한다.
3. 별도 lab 계정과 테스트 window를 기록한다.
4. 아래 scope wrapper의 dry run을 검토한 뒤에만 실행 모드를 사용한다.

Kali를 먼저 설치하는 목적은 공격 도구 확보 자체가 아니다. Wazuh 수집, 탐지 규칙, Telegram 알림, 대상 snapshot, scope guard를 먼저 준비한 뒤 통제된 이벤트를 발생시켜 탐지 품질을 검증하기 위한 트래픽 발생기다.

## Scope-Enforced Initial Scan

초기 포트 baseline은 대상 제한 wrapper를 사용한다. 기본 실행은 dry run이며 CIDR, hostname, 다른 IP, NSE script, service detection을 받지 않는다.

```bash
./scripts/kali-purple-team-scan.sh --target 192.168.0.77

PURPLE_TEAM_ACK=ODJ-VERIFY01:192.168.0.77 \
  ./scripts/kali-purple-team-scan.sh --target 192.168.0.77 --execute
```

실행 결과는 기본적으로 Git에서 제외되는 `artifacts/kali-validation/`에 저장한다. 이 wrapper는 운영 실수를 줄이는 보조 통제이며 VLAN 또는 Proxmox firewall 격리를 대체하지 않는다.

## Telegram Notification Boundary

Telegram 알림은 High/Critical analyst notification 용도로만 사용한다. Bot token, chat ID, webhook URL은 repo에 저장하지 않고 vault 또는 environment variable로만 전달한다. 자동 차단, 자동 격리, 계정 잠금 같은 대응은 이 단계의 범위가 아니다.

초기 권장 기준:

- rule `100502` Windows failed logon burst
- rule `100505` Defender malware detection
- Wazuh agent disconnect가 일정 시간 이상 지속되는 경우

2026-07-25에 Telegram notifier를 활성화했고 direct delivery, queued alert 7건, 1분 주기 반복 실행을 검증했다. Runtime secret은 Wazuh host의 권한 제한 파일에만 있으며 Git에는 저장하지 않는다.
