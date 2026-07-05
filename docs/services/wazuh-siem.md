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
| 전체 서버 | package log, active response log, baseline FIM |

## 적용 순서

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook playbooks/wazuh-server.yml
ansible-playbook playbooks/wazuh-agent-deploy.yml
ansible-playbook playbooks/wazuh-agent-logs.yml
ansible-playbook playbooks/wazuh-custom-detections.yml
ansible-playbook playbooks/wazuh-platform-hardening.yml
ansible-playbook playbooks/wazuh-index-lifecycle.yml
```

## 검증

```bash
ansible all:!wazuh_server -b -m command -a 'systemctl is-active wazuh-agent'
ansible wazuh_server -b -m command -a '/var/ossec/bin/agent_control -lc'
ansible all -b -m command -a 'systemctl --failed --no-legend --no-pager'
```

정상 기준:

- Wazuh manager/indexer/dashboard active
- 모든 managed server의 `wazuh-agent` active
- Wazuh manager의 `agent_control -lc`에서 전체 agent Active
- 전체 서버 failed unit 없음
- SME custom detection fixture test 통과
- Wazuh 4.10.4 component hold, API loopback bind, 내부망 UFW 제한
- Alert index 30일 retention 및 일일 snapshot timer

## 운영 기준

- agent 배포는 `playbooks/wazuh-agent-deploy.yml`을 기준으로 한다.
- 역할별 로그 수집은 `playbooks/wazuh-agent-logs.yml`로 관리한다.
- Keycloak은 현재 파일 로그가 아니라 systemd journal에 로그를 남기므로 journald 수집을 기준으로 한다.
- 향후 AI 방어형 분석은 Wazuh alert를 우선 정규화한 뒤 요약/분류/대응 추천 단계로 붙인다.
Hardening, custom detection, AI pipeline의 상세 설계는 docs/services/wazuh-hardening-ai-defense.md를 기준으로 한다.
