# Wazuh Custom Detection Runbook

이 문서는 SME 환경의 Wazuh custom decoder와 rule을 fixture 기반으로 배포하고 검증하는 절차다.

## 적용

    cd /home/sysadmin/homelab-infra/ansible
    ansible-playbook playbooks/wazuh-custom-detections.yml

playbook은 기존 custom 파일을 메모리에 백업하고 Ansible timestamp backup을 남긴 뒤 새 decoder/rule을 설치한다. 이어서 analysis configuration과 fixture를 검증한다. 검증 실패 시 메모리 백업으로 이전 파일을 복원하며 manager를 재시작하지 않는다. 모든 검증이 성공한 경우에만 wazuh-manager를 재시작하고, TCP 1514 receiver와 전체 managed agent의 Active 복귀를 확인해야 성공으로 종료한다.

## Rule catalog

| Rule | Level | Detection |
|---|---:|---|
| 100101 | 6 | Nextcloud login failure |
| 100102 | 10 | 동일 source의 120초 내 Nextcloud login failure 5회 |
| 100201 | 6 | Keycloak LOGIN_ERROR |
| 100202 | 10 | 동일 source IP의 120초 내 Keycloak LOGIN_ERROR 5회 |
| 100301 | 10 | 동일 source IP의 120초 내 Dovecot invalid login 5회 |
| 100401 | 8 | Samba AD replication bind authentication failure |
| 100500 | 0 | JSON fixture/integration Windows event parent |
| 100501 | 7 | Windows Security Event ID 4625 failed logon |
| 100502 | 10 | 동일 source의 120초 내 Windows failed logon 5회 |
| 100503 | 3 | Windows Security Event ID 4624 interactive/RDP logon type 2 or 10 |
| 100504 | 5 | Windows PowerShell Event ID 4104 JSON integration validation marker |
| 100505 | 12 | Microsoft Defender Event ID 1116 malware detection |

100200은 Keycloak event의 parent rule이며 level 0이라 alert를 생성하지 않는다. Windows rule은 Kali purple-team validation의 초기 증거 수집 기준으로 사용한다.

Windows agent의 live EventChannel log는 `windows_eventchannel` decoder와 built-in Windows rule tree로 처리된다. JSON fixture와 integration event는 level 0 parent `100500`으로 묶는다. Rule `100501`, `100503`, `100504`, `100505`는 정확한 live parent와 fixture parent를 함께 참조하고 provider, channel, event ID field를 검증한다. `100503`은 network/service logon type `3`을 제외하고 console interactive `2`와 RDP `10`만 허용한다.

`100504`는 JSON fixture 또는 integration event에서 `WAZUH_4104_VALIDATION_` marker를 검증하는 level 5 rule이다. Live `windows_eventchannel` parent에는 연결하지 않는다. 모든 live 4104를 custom rule로 덮어쓰면 내장 `91803` 이후 탐지의 원래 심각도를 낮추거나 Telegram 알림을 불필요하게 늘릴 수 있기 때문이다. 실제 PowerShell 행위는 Wazuh built-in `918xx` rule의 심각도를 따른다. `100505`는 내장 Defender 1116 rule `62123` 뒤에 같은 level 12로 연결해 malware 탐지 심각도를 보존한다.

기본 Windows agent 설정은 Application, Security, System channel만 수집하므로 `100504`와 `100505`를 live 검증하려면 `playbooks/wazuh-agent-windows.yml`의 중앙 `windows` group shared config를 적용해야 한다.

PowerShell collection의 live 검증은 endpoint에서 Event ID `4104`를 발생시킨 뒤 built-in `918xx` alert와 `windows_eventchannel` decoder를 확인한다. 단순한 benign script까지 기록하려면 endpoint의 PowerShell Script Block Logging 정책을 별도로 활성화해야 하며, 이 설정은 script content 수집 범위를 넓히므로 명시적 승인 없이 적용하지 않는다. Defender `1116` live 검증은 별도 승인된 test artifact가 있을 때만 수행한다.

## Fixture

redacted fixture는 ansible/files/wazuh/fixtures에 저장한다. 실제 사용자명, realm ID, request ID, IP는 문서용 값으로 치환하며 password, token, cookie, mail body는 저장하지 않는다.

    ansible wazuh_server -b -m command \
      -a '/var/ossec/bin/test-sme-detections /var/ossec/etc/sme-detection-fixtures'

현재 test runner는 단건 rule, burst correlation, Windows network logon type 3 negative fixture를 함께 검증한다.

## 변경 절차

1. redacted positive fixture와 필요한 negative fixture를 추가한다.
2. decoder와 rule을 수정한다.
3. playbook을 실행해 analysisd validation과 fixture test를 통과시킨다.
4. verify-all playbook을 실행한다.
5. 실제 alert volume과 false positive를 관찰한다.

재시작 후 문제가 발견되면 `/var/ossec/etc/rules/sme_rules.xml.*~`와 `/var/ossec/etc/decoders/sme_decoders.xml.*~` 중 해당 apply 직전 timestamp backup을 원래 경로로 복원한다. 그 뒤 `/var/ossec/bin/wazuh-analysisd -t`를 통과한 경우에만 `systemctl restart wazuh-manager`를 실행한다.

AI pipeline은 이 rule output을 canonical event로 정규화하며, 원본 full_log를 직접 외부 모델로 전송하지 않는다.
