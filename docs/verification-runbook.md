# Full Verification Runbook

이 문서는 Terraform부터 AD, Keycloak, Nextcloud, Mail, Storage, Wazuh까지 현재 운영 기준을 변경 없이 한 번에 검증하는 절차다.

## 사전 조건

- 컨트롤 노드에서 모든 inventory host로 SSH와 sudo가 가능해야 한다.
- terraform 디렉터리에 provider 초기화 결과인 .terraform이 있어야 한다.
- 내부 DNS에서 mail01.toss.lan을 조회할 수 있어야 한다.
- 검증 playbook은 서비스 구성을 변경하지 않지만 Keycloak CLI 인증 세션 파일을 갱신할 수 있다.

## 전체 검증

    cd /home/sysadmin/homelab-infra/ansible
    ansible-playbook playbooks/verify-all.yml

| 영역 | 정상 기준 |
|---|---|
| Terraform | fmt check와 validate 통과 |
| Baseline | 전체 host ping 성공, failed unit 없음, NTP synchronized |
| AD | 양쪽 samba-ad-dc active, replication 정상, FSMO 5개 role 확인 |
| Storage | nfs-server, smbd active |
| Keycloak | keycloak, haproxy active, realm discovery endpoint HTTP 200 |
| Nextcloud | Apache/MariaDB/cron active, maintenance off, cron mode, Mail/Talk enabled |
| Mail | Postfix/Dovecot/autoconfig active, 25/587/993 listen 및 Nextcloud에서 접근 가능 |
| Wazuh | manager/indexer/dashboard active, 전체 managed agent Active |
| Timers | certificate monitor와 active DC backup timer enabled |
| Identity | AD → Keycloak → Nextcloud realm/client/group/storage/addressbook 검증 통과 |

## 영역별 재실행

    ansible-playbook playbooks/verify-all.yml --tags ad
    ansible-playbook playbooks/verify-all.yml --tags nextcloud,mail
    ansible-playbook playbooks/verify-all.yml --tags wazuh
    ansible-playbook playbooks/verify-all.yml --tags identity
    ansible-playbook playbooks/verify-all.yml --tags terraform

사용 가능한 tag는 terraform, baseline, ad, storage, keycloak, nextcloud, mail, wazuh, timers, identity다.

## 실패 처리

1. 첫 실패 task의 host, 명령, stderr를 확인한다.
2. 해당 영역 tag로 재현한다.
3. 서비스 로그와 기존 영역별 runbook을 확인한다.
4. 수정 후 영역별 검증을 통과시키고 마지막에 전체 playbook을 다시 실행한다.

이 playbook은 복구 작업을 수행하지 않는다. 특히 DC failover, Nextcloud repair, 서버 재구축 playbook은 자동 호출하지 않는다.

## 결과 기록

    cd /home/sysadmin/homelab-infra/ansible
    mkdir -p ../artifacts/verification
    ansible-playbook playbooks/verify-all.yml \
      | tee ../artifacts/verification/verify-all-$(date -u +%Y%m%dT%H%M%SZ).log

artifacts 디렉터리는 운영 로그이므로 secret 출력 여부를 검토한 뒤 보관 정책에 따라 관리한다.
