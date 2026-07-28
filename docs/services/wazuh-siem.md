# Wazuh SIEM Runbook

Wazuh는 `sme-security-infra`의 SIEM/XDR 기준점이다. 목표는 단순 agent 설치가 아니라 AD, IAM, 협업, 메일, 스토리지 계층의 보안 이벤트를 한 곳에서 수집하는 것이다.

## 구성 요소

| 대상 | 수집 기준 |
|---|---|
| `dc01`, `dc02` | journald, Samba AD 로그 |
| `keycloak` | journald 기반 Keycloak 로그인/LDAP federation 이벤트 |
| `nextcloud` | Nextcloud app log, Apache access/error log, journald |
| `mail01` | Postfix/Dovecot mail log, auth log, syslog |
| `storage01` | Samba/SMB 로그, journald |
| `win-mgmt01`, `odj-verify01` | Windows Event Log, syscollector, FIM baseline |
| 전체 Linux 서버 | package log, active response log, baseline FIM |

## 적용 순서

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook playbooks/wazuh-server.yml
ansible-playbook playbooks/wazuh-agent-deploy.yml
ansible-playbook playbooks/wazuh-agent-logs.yml
ansible-playbook playbooks/wazuh-agent-windows.yml
ansible-playbook playbooks/wazuh-custom-detections.yml
ansible-playbook playbooks/wazuh-platform-hardening.yml
ansible-playbook playbooks/wazuh-index-lifecycle.yml
```

## 검증

```bash
ansible linux_managed -b -m command -a 'systemctl is-active wazuh-agent'
ansible windows_management:windows_endpoint_pilot -e ansible_become=false -m ansible.windows.win_service_info -a 'name=WazuhSvc'
ansible wazuh_server -b -m command -a '/var/ossec/bin/agent_control -lc'
ansible linux_managed:wazuh_server -b -m command -a 'systemctl --failed --no-legend --no-pager'
```

정상 기준:

- Wazuh manager/indexer/dashboard active
- 모든 Linux managed server의 `wazuh-agent` active
- Windows endpoint의 `WazuhSvc` started
- Wazuh manager의 `agent_control -lc`에서 전체 agent Active
- 전체 Linux 서버 failed unit 없음
- SME custom detection fixture test 통과
- Wazuh 4.10.4 component hold, API loopback bind, 내부망 UFW 제한
- Alert index 30일 retention 및 일일 snapshot timer

## 운영 기준

- Linux agent 배포는 `playbooks/wazuh-agent-deploy.yml`을 기준으로 하고 `linux_managed` inventory group만 대상으로 한다.
- Windows agent 배포는 `playbooks/wazuh-agent-windows.yml`을 기준으로 하며 `windows_management`와 `windows_endpoint_pilot`을 대상으로 한다. Windows 대상은 `localadmin` OpenSSH key auth와 관리자 권한이 선행 조건이다.
- 같은 playbook은 Wazuh `windows` group의 shared `agent.conf`에 PowerShell Operational과 Microsoft Defender Operational EventChannel 수집을 배포한다. Candidate를 `verify-agent-conf`로 먼저 검증하고 active file backup은 sync directory 밖의 `/var/backups/wazuh-windows-agent-conf/`에 저장한다. Ansible 기본 timestamp backup은 파일명에 colon이 들어가 Windows agent unmerge를 실패시키므로 shared directory 안에서 사용하지 않는다.
- Live PowerShell 4104는 Wazuh built-in `918xx` rule tree를 사용한다. Custom `100504`는 JSON fixture/integration marker 전용이며 live 내장 심각도를 덮어쓰지 않는다.
- Defender Event ID `1116`은 built-in rule `62123`과 custom rule `100505` 모두 level 12를 유지한다. EICAR를 포함한 test artifact 생성은 별도 승인 전에는 실행하지 않는다.
- `playbooks/wazuh-agent-windows.yml`의 `wazuh_windows_script_block_logging_state` 기본값은 `observe`다. `enabled` 또는 rollback용 `disabled`를 명시한 실행만 endpoint registry를 변경한다. Script Block Logging은 명령 내용이 보안 로그로 수집될 수 있으므로 change window와 민감정보 노출 검토 후 승인한다.
- 역할별 Linux 로그 수집은 `playbooks/wazuh-agent-logs.yml`로 관리한다.
- Wazuh manager에 남은 폐기 VM agent는 `/var/ossec/bin/manage_agents -r <ID>`로 제거하되, `agent_control -l`에서 이름과 상태를 먼저 확인한다.
- Keycloak은 현재 파일 로그가 아니라 systemd journal에 로그를 남기므로 journald 수집을 기준으로 한다.
- 향후 AI 방어형 분석은 Wazuh alert를 우선 정규화한 뒤 요약/분류/대응 추천 단계로 붙인다.
- Kali 기반 endpoint 검증은 `docs/operations/kali-purple-team-validation.md`의 scope와 stop condition을 따른다. 초기 target은 `ODJ-VERIFY01` 한 대로 제한한다.
- Telegram 같은 외부 알림은 High/Critical analyst notification으로만 사용하며 bot token, chat ID, webhook URL은 repo에 저장하지 않는다.
Hardening, custom detection, AI pipeline의 상세 설계는 docs/services/wazuh-hardening-ai-defense.md를 기준으로 한다.

Telegram 전송은 `wazuh-ai-telegram-notifier.timer`로 분리되어 있으며 기본값은 disabled다. `wazuh_ai_telegram_enabled=true`와 외부 secret 주입이 모두 준비된 뒤에만 켠다.

Pilot endpoint의 PowerShell Script Block Logging 정책을 승인 후 적용하거나 rollback할 때만 다음 명령을 사용한다.

```bash
cd /home/sysadmin/homelab-infra/ansible

ansible-playbook -i inventory/hosts playbooks/wazuh-agent-windows.yml \
  --limit odj-verify01 \
  -e wazuh_windows_script_block_logging_state=enabled

ansible-playbook -i inventory/hosts playbooks/wazuh-agent-windows.yml \
  --limit odj-verify01 \
  -e wazuh_windows_script_block_logging_state=disabled
```

기본 `observe` 실행은 해당 registry를 생성하거나 삭제하지 않는다. 적용 전후 `HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging`의 `EnableScriptBlockLogging` 값을 기록한다.
