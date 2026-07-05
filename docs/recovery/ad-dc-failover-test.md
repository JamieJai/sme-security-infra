# AD DC 장애 전환 시험 Runbook

ansible/playbooks/ad-dc-failover-test.yml은 비활성 DC의 Samba 서비스를
일시 중지하고 핵심 서비스가 active DC로 계속 동작하는지 검증한다.

기본 시험 대상은 dc01이며 active_dc 그룹에 포함된 DC는 안전 조건에
의해 중지가 거부된다.

## 실행

    cd ansible
    ansible-playbook -i inventory/hosts \
      playbooks/ad-dc-failover-test.yml \
      --vault-password-file .vault_pass

## 안전장치

- Samba 중지 전에 10분 후 자동 재시작하는 transient systemd timer를 등록한다.
- Ansible always 블록에서도 Samba 시작과 timer 해제를 수행한다.
- 시험 대상이 active_dc이면 실행을 중단한다.
- Samba DB 삭제, metadata cleanup, FSMO 변경, DC 재가입은 수행하지 않는다.
- 실패한 검증이 있어도 DC 복구와 복제 확인 후 최종 실패를 반환한다.

## 검증 항목

- survivor DC의 Samba, DB, SYSVOL, machine trust, DNS
- Administrator Kerberos 인증
- Keycloak readiness, 로컬 HA LDAPS, changed-user sync
- Postfix와 Dovecot 서비스, LDAPS, 실제 Dovecot 인증
- Nextcloud 상태
- 시험 DC 복구 후 DRS, SYSVOL, machine trust
