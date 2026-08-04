# Security Threat Analysis and Response Campaign

이 campaign은 방화벽, endpoint, network 위협을 개인 lab에서 통제된 이벤트로
재현하고 탐지, 분석, 대응, 복구, 재발 방지 증적까지 남기기 위한 실행 기준이다.
Kali 도구 사용 자체가 목적이 아니며 모든 live traffic은 `kali01`에서
`ODJ-VERIFY01` 한 대로 제한한다.

## 경험 증명 기준

각 시나리오는 다음 다섯 단계가 모두 있어야 완료로 본다.

1. **Detect:** endpoint 원본 event와 Wazuh alert를 확인한다.
2. **Analyze:** source, target, port/process/account, 영향 범위를 식별한다.
3. **Contain:** source 차단, 계정 보호 또는 endpoint 격리 판단을 기록한다.
4. **Recover:** 임시 정책을 rollback하고 agent/service 정상 상태를 확인한다.
5. **Improve:** rule, audit policy, deployment gate 또는 runbook을 보강한다.

자동 차단은 적용하지 않는다. 탐지 결과가 test window와 일치하는지 분석한 뒤
승인된 대응만 수행한다.

## Campaign Matrix

| 영역 | 통제된 위협 | 원본 증거 | Wazuh 기준 | 대응 증거 | 현재 상태 |
|---|---|---|---|---|---|
| Firewall/Network | 고정 5-port connection scan | Security 5157, source `.37`, target `.77` | `100506`, burst `100507` | Kali guard 유지, target rule 불변, audit rollback | fixture 준비 |
| Endpoint/Auth | 전용 lab 계정 실패 로그인 5회 | Security 4625 | `100501`, burst `100502` | lockout 확인, source/account containment 판단 | 단건 live 완료, burst 예정 |
| Endpoint/PowerShell | benign validation marker | PowerShell 4104 | built-in `918xx` | process/script 분석, policy rollback | collection live 완료, policy 예정 |
| Endpoint/Defender | EICAR test artifact | Defender 1116 | `100505` level 12 | quarantine 확인, artifact 제거, Defender health | fixture 준비 |

## Phase 1: Firewall and Network Visibility

Windows Filtering Platform Event 5157은 차단된 connection의 source/destination,
port, protocol, application, filter runtime ID를 제공한다. Packet Drop 5152는
packet마다 발생해 volume이 매우 높을 수 있으므로 초기 campaign은 connection
failure 5157만 사용한다.

준비된 안전장치:

- audit policy 기본값 `observe`, baseline 기본값 `unconfirmed`
- 변경 target은 `windows_endpoint_pilot` group으로 제한
- 최초 target은 `odj-verify01`만 허용
- 기존 상태가 `No Auditing`일 때만 pilot enable 허용
- success auditing은 끄고 failure만 활성화
- 확인한 `No Auditing` baseline으로만 rollback
- Kali egress는 `.77`과 5개 TCP port만 허용

Live enable 전 확인:

```bash
cd ansible
ansible odj-verify01 -i inventory/hosts -m ansible.windows.win_command \
  -a 'auditpol.exe /get /subcategory:"Filtering Platform Connection"'
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags wazuh
```

`auditpol` 원본 출력은 evidence에 기록한다. 기존 상태가 `No Auditing`이 아니면
playbook이 enable을 거부한다. 이 경우 기존 설정과 동일한 restore path를 먼저
설계하고 별도 승인하기 전에는 변경하지 않는다.

승인 후 pilot만 활성화:

```bash
cd ansible
ansible-playbook -i inventory/hosts playbooks/wazuh-agent-windows.yml \
  --limit odj-verify01 \
  -e '{"wazuh_windows_filtering_platform_audit_state":"enabled","wazuh_windows_filtering_platform_audit_targets":["odj-verify01"],"wazuh_windows_filtering_platform_audit_baseline":"no_auditing"}'
```

그 뒤 기존 fixed-scope scan wrapper를 한 번 실행하고 5157 source/destination/port,
rule `100506/100507`, agent Active, Telegram queue를 확인한다. 기존 Windows
Firewall allow rule은 넓히지 않는다.

`No Auditing` baseline을 확인하고 enable한 경우에만 다음 rollback을 실행한다.
기존 baseline이 달랐다면 `disabled` rollback을 사용하지 않는다.

```bash
cd ansible
ansible-playbook -i inventory/hosts playbooks/wazuh-agent-windows.yml \
  --limit odj-verify01 \
  -e '{"wazuh_windows_filtering_platform_audit_state":"disabled","wazuh_windows_filtering_platform_audit_targets":["odj-verify01"],"wazuh_windows_filtering_platform_audit_baseline":"no_auditing"}'
```

## Phase 2: Endpoint Authentication

- 전용 lab 계정과 lockout threshold를 먼저 확인한다.
- 존재하지 않는 identity 또는 전용 계정만 사용한다.
- 최대 5회, 120초 window를 넘기지 않는다.
- account lockout이나 예상 외 host traffic이 발생하면 즉시 중단한다.
- 4625 단건과 burst alert를 확인하고 정상 network logon type 3이 interactive
  success rule `100503`으로 오탐되지 않는지 확인한다.

## Phase 3: PowerShell and Defender

PowerShell은 pilot에서 Script Block Logging을 명시적으로 활성화한 window에 benign
marker만 실행하고 built-in `918xx` severity를 보존한다. Defender는 Microsoft가
제공하는 EICAR test artifact만 사용하며 생성 전 snapshot, Defender health,
자동 quarantine, artifact 제거 절차를 확인한다.

Defender test는 malware 실행이나 exploit이 아니다. 그래도 endpoint 보안 제품을
의도적으로 동작시키므로 별도 승인 없이 생성하지 않는다.

## Evidence Checklist

- ticket/reference와 approver
- KST/UTC start and end
- source/target/port 또는 account/process
- endpoint raw event ID와 Wazuh rule ID
- detection latency와 alert severity
- 영향 받은 host/account/service 범위
- containment decision과 실제 변경 여부
- rollback 결과, Wazuh agent Active, TCP 1514
- false positive/negative와 개선 commit
- secret이 제거된 artifact hash와 operations DB verification ID

## Stop Conditions

- target이 `192.168.0.77` 밖으로 확대됨
- DC, identity, mail, storage, Nextcloud로 traffic 발생
- 계정 잠금 또는 endpoint/agent disconnect
- Wazuh TCP 1514 중단 또는 managed agent 비활성
- 예상보다 높은 event volume
- credential, token, private data 노출

중단 시 추가 이벤트를 만들지 않고 WFP audit policy와 임시 endpoint 정책을
rollback한 뒤 health verification부터 수행한다.

## References

- [Microsoft Event 5157](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/auditing/event-5157)
- [Microsoft Filter Origin Audit Log](https://learn.microsoft.com/en-us/windows/security/operating-system-security/network-security/windows-firewall/filter-origin-documentation)
