# Wazuh Platform Hardening Runbook

이 문서는 Wazuh 4.10.4 all-in-one 환경의 package, API, firewall, TLS 운영 기준을 적용하고 검증하는 절차다.

## 적용

    cd /home/sysadmin/homelab-infra/ansible
    ansible-playbook playbooks/wazuh-platform-hardening.yml

## 적용 기준

- wazuh-manager, wazuh-indexer, wazuh-dashboard 버전 4.10.4-1 검증 및 hold
- installer script SHA-256 고정
- Wazuh API 55000을 127.0.0.1로 제한
- API login 10회 실패 시 300초 block
- API 분당 request 300회 제한
- API upload 크기 10 MiB 제한
- 1514, 1515, 443은 192.168.0.0/24에서만 UFW 허용
- 55000, 9200 외부 UFW 허용 제거
- dashboard/indexer/API HTTPS와 private key 0400 검증

SSH 22 정책은 원격 잠금 방지를 위해 이 playbook에서 변경하지 않는다.

## 검증

    ansible-playbook playbooks/wazuh-platform-hardening.yml
    ansible-playbook playbooks/verify-all.yml --tags wazuh

두 번째 hardening 실행은 changed=0이어야 한다. API와 indexer는 localhost에서 인증 없이 각각 401을 반환하고 dashboard는 login page를 반환해야 한다.

## Version upgrade

현재 repository candidate가 validated version보다 높아도 hold를 유지한다. Upgrade 시에는 다음 순서를 따른다.

1. index snapshot과 Wazuh configuration backup을 확인한다.
2. staging 또는 VM snapshot에서 target version을 검증한다.
3. manager, indexer, dashboard와 agent 호환성을 확인한다.
4. version/checksum 변수와 fixture 기대값을 갱신한다.
5. hold를 의도적으로 해제하고 upgrade한다.
6. custom detection과 full verification을 다시 실행한다.

## 남은 hardening

현재 dashboard certificate SAN은 localhost 중심의 installer 인증서다. 내부 사용자의 hostname 검증을 위해 wazuh.toss.lan과 192.168.0.30 SAN을 포함한 인증서 교체가 필요하다. 이 작업은 dashboard trust 배포와 rollback을 포함한 별도 certificate rotation으로 수행한다.

공용 admin 제거, analyst/read-only RBAC 분리, index snapshot repository와 30일 retention도 다음 단계에서 적용한다.
