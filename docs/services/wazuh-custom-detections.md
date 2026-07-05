# Wazuh Custom Detection Runbook

이 문서는 SME 환경의 Wazuh custom decoder와 rule을 fixture 기반으로 배포하고 검증하는 절차다.

## 적용

    cd /home/sysadmin/homelab-infra/ansible
    ansible-playbook playbooks/wazuh-custom-detections.yml

playbook은 기존 custom 파일을 메모리에 백업하고 새 decoder/rule을 설치한 뒤 analysis configuration과 fixture를 검증한다. 검증 실패 시 이전 파일을 복원하며 manager를 재시작하지 않는다. 모든 검증이 성공한 경우에만 wazuh-manager를 재시작한다.

## Rule catalog

| Rule | Level | Detection |
|---|---:|---|
| 100101 | 6 | Nextcloud login failure |
| 100102 | 10 | 동일 source의 120초 내 Nextcloud login failure 5회 |
| 100201 | 6 | Keycloak LOGIN_ERROR |
| 100202 | 10 | 동일 source IP의 120초 내 Keycloak LOGIN_ERROR 5회 |
| 100301 | 10 | 동일 source IP의 120초 내 Dovecot invalid login 5회 |
| 100401 | 8 | Samba AD replication bind authentication failure |

100200은 Keycloak event의 parent rule이며 level 0이라 alert를 생성하지 않는다.

## Fixture

redacted fixture는 ansible/files/wazuh/fixtures에 저장한다. 실제 사용자명, realm ID, request ID, IP는 문서용 값으로 치환하며 password, token, cookie, mail body는 저장하지 않는다.

    ansible wazuh_server -b -m command \
      -a '/var/ossec/bin/test-sme-detections /var/ossec/etc/sme-detection-fixtures'

현재 test runner는 단건 rule과 burst correlation을 함께 검증한다.

## 변경 절차

1. redacted positive fixture와 필요한 negative fixture를 추가한다.
2. decoder와 rule을 수정한다.
3. playbook을 실행해 analysisd validation과 fixture test를 통과시킨다.
4. verify-all playbook을 실행한다.
5. 실제 alert volume과 false positive를 관찰한다.

AI pipeline은 이 rule output을 canonical event로 정규화하며, 원본 full_log를 직접 외부 모델로 전송하지 않는다.
