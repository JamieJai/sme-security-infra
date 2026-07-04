# Wazuh Index Lifecycle Runbook

Wazuh alert index의 보존 기간과 filesystem snapshot 운영 기준이다.

## 적용

    cd /home/sysadmin/homelab-infra/ansible
    ansible-playbook playbooks/wazuh-index-lifecycle.yml

적용 내용:

- wazuh-alerts-4.x-* index에 30일 ISM retention 적용
- 향후 alert index에 ISM template 자동 적용
- 기존 unmanaged alert index에 동일 policy 연결
- /var/backups/wazuh-indexer filesystem repository 등록
- 매일 02:30 KST snapshot 실행
- 90일보다 오래된 일일 snapshot을 API로 삭제
- snapshot에는 alert index만 포함하고 global cluster state는 제외

OpenSearch 공식 문서가 권고하는 대로 broad * pattern 대신 wazuh-alerts-4.x-* prefix만 사용한다. Security system index에는 retention policy를 적용하지 않는다.

## 검증

    ansible-playbook playbooks/wazuh-index-lifecycle.yml
    ansible-playbook playbooks/verify-all.yml --tags wazuh
    ansible wazuh_server -b -m command -a 'systemctl list-timers wazuh-alert-snapshot.timer --no-pager'

두 번째 lifecycle 실행은 changed=0이어야 한다.

## 수동 snapshot

    ansible wazuh_server -b -m command -a 'systemctl start wazuh-alert-snapshot.service'

같은 UTC 날짜의 snapshot이 이미 있으면 script는 중복 생성하지 않는다.

## Restore test

운영 cluster에 직접 restore하지 않는다. VM snapshot 또는 격리된 test indexer에서 repository를 등록한 뒤 다음 순서로 검증한다.

1. snapshot state가 SUCCESS인지 확인한다.
2. 별도 test cluster에서 snapshot repository를 등록한다.
3. rename_pattern과 rename_replacement를 사용해 test prefix로 restore한다.
4. document count와 대표 alert query를 비교한다.
5. test index를 삭제하고 결과를 기록한다.

현재 repository는 동일 VM의 로컬 disk에 있으므로 VM/disk 장애를 견디지 못한다. 다음 단계에서 storage01 또는 별도 backup target으로 복제해야 한다.
