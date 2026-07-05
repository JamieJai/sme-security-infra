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

운영 snapshot repository는 로컬 disk에 있고, 아래 절차로 storage01에 별도 사본을 유지한다.

## storage01 외부 복제

`wazuh-snapshot-replica.yml`은 `storage01:/data/backups/wazuh-indexer`를 Wazuh
호스트에만 NFS export한다. `all_squash`와 전용 UID/GID 1900을 사용하므로 원격
root 권한은 storage01에 전달되지 않는다. Wazuh는 매일 03:15 KST 이후 최대
15분의 지연을 두고 snapshot repository 전체를 동기화한다.

    ansible-playbook -i inventory/hosts playbooks/wazuh-snapshot-replica.yml

검증은 마지막 성공 marker가 36시간 이내인지 확인하고 외부 사본을
`wazuh-alerts-offsite` read-only repository로 등록해 SUCCESS snapshot을 조회한다.
운영 cluster에는 restore하지 않는다. 실제 월간 restore는 별도 test indexer를
inventory에 추가한 뒤 외부 repository에서 임시 index로 복원하고 삭제해야 한다.

## 월간 restore test

`wazuh-restore-test.yml`은 운영 indexer와 다른 cluster name, data/config/log 경로,
HTTP 19201, transport 19301, 512MB heap을 사용하는 임시 indexer를 구성한다.
매월 외부 replica의 최신 SUCCESS snapshot을 `restore-test-*` index로 실제 복원해
shard 성공, cluster health, document count를 검증하고 즉시 삭제·종료한다.
성공 기록은 `/var/lib/wazuh-restore-test-state/last-success`에 남으며 35일을 넘으면
`verify-all.yml`이 실패한다.
