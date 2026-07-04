# Session Handoff - 2026-07-04 Wazuh Hardening

이 문서는 docs/session-handoff-2026-07-04.md 이후 진행한 verification과 Wazuh 작업의 최신 인계 기준이다.

기준 repo: /home/sysadmin/homelab-infra

remote: git@github.com:JamieJai/sme-security-infra.git

## 완료한 작업

### 전체 verification

- ansible/playbooks/verify-all.yml
- docs/verification-runbook.md
- Terraform, 전체 host baseline, AD/FSMO, Keycloak, Nextcloud, Mail, Storage, Wazuh, timer, identity flow 검증
- 최종 결과: 모든 host failed=0, unreachable=0

### Wazuh custom detection

- Fixture 기반 decoder/rule 배포와 실패 시 rollback
- Keycloak, Nextcloud, Dovecot, Samba AD detection 7개 검사 통과
- Rule 100101/100102: Nextcloud login failure와 burst
- Rule 100201/100202: Keycloak LOGIN_ERROR와 burst
- Rule 100301: Dovecot invalid login burst
- Rule 100401: Samba replication bind authentication failure
- 정상 재실행 changed=0

관련 파일:

- ansible/playbooks/wazuh-custom-detections.yml
- ansible/files/wazuh/decoders/sme_decoders.xml
- ansible/files/wazuh/rules/sme_rules.xml
- ansible/files/wazuh/fixtures
- docs/wazuh-custom-detections.md

### Wazuh platform hardening

- Manager/indexer/dashboard 4.10.4-1 검증 및 hold
- Installer SHA-256 고정
- API 55000을 127.0.0.1로 제한
- API login/rate/upload 제한
- 1514, 1515, 443은 192.168.0.0/24에서만 UFW 허용
- 55000, 9200 broad allow 제거
- HTTPS endpoint와 private key 0400 검증
- 정상 재실행 changed=0

관련 파일:

- ansible/playbooks/wazuh-platform-hardening.yml
- ansible/roles/wazuh-server/defaults/main.yml
- ansible/roles/wazuh-server/tasks/main.yml
- docs/wazuh-platform-hardening.md

주의:

- SSH 22는 원격 잠금 방지를 위해 변경하지 않았다.
- Dashboard certificate SAN은 현재 127.0.0.1 중심이다.
- 기존 CA private key가 없어 인증서 재발급은 trust 배포/rollback과 함께 별도 진행한다.

### Wazuh index lifecycle

- wazuh-alerts-4.x-* 전용 30일 ISM retention
- 기존 index policy 연결과 향후 index template 적용
- Local repository: /var/backups/wazuh-indexer
- 일일 snapshot: 02:30 KST, randomized delay 15분
- Snapshot 보존 90일
- Initial snapshot SUCCESS
- 연속 재실행 changed=0

관련 파일:

- ansible/playbooks/wazuh-index-lifecycle.yml
- ansible/files/wazuh/index-lifecycle
- docs/wazuh-index-lifecycle.md

보안 결정:

- Broad wildcard는 사용하지 않는다.
- Security system index에는 delete policy를 적용하지 않는다.
- Snapshot에는 alert index만 포함하고 global cluster state는 제외한다.

제약:

- Snapshot repository가 Wazuh VM의 동일 disk에 있다.
- VM/disk 장애 대응을 위해 storage01 또는 별도 target 복제가 필요하다.

### AI defense 설계

관련 문서: docs/wazuh-hardening-ai-defense.md

    Wazuh alerts.json
      -> durable offset collector
      -> bounded spool
      -> normalizer/redactor
      -> deterministic correlation
      -> AI enrichment
      -> analyst notification

통제 기준:

- AI worker에는 Wazuh write API, SSH, shell, identity admin API 권한을 주지 않는다.
- AI 결과만으로 계정 잠금, 방화벽 차단, 파일 삭제를 실행하지 않는다.
- Full log를 외부 모델로 직접 전송하지 않는다.
- 초기 운영은 notification 없는 shadow mode다.

## 현재 검증 상태

    terraform fmt -check -recursive: pass
    terraform validate: pass
    Wazuh custom detection: 7 checks pass
    Wazuh platform hardening: pass, changed=0
    Wazuh index lifecycle: pass, changed=0
    Wazuh initial snapshot: SUCCESS
    full verify-all: failed=0, unreachable=0

## 실행 순서

    cd /home/sysadmin/homelab-infra/ansible
    ansible-playbook playbooks/wazuh-custom-detections.yml
    ansible-playbook playbooks/wazuh-platform-hardening.yml
    ansible-playbook playbooks/wazuh-index-lifecycle.yml
    ansible-playbook playbooks/verify-all.yml

## 다음 계획

### 1. Snapshot 외부 복제와 restore test

- storage01에 backup 전용 경로 생성
- Root squash와 최소 권한을 포함한 NFS 또는 rsync-over-SSH 방식 결정
- Local snapshot을 외부 target으로 복제
- 격리된 test indexer에서 restore test
- 복제 실패와 stale backup 경보

완료 기준:

- Wazuh VM disk 손실 시에도 snapshot 접근 가능
- 월 1회 restore test 성공 기록
- 마지막 성공 snapshot age가 verification에 포함

### 2. Dashboard certificate rotation

- wazuh.toss.lan, 192.168.0.30, 필요 시 127.0.0.1 SAN
- 새 CA 또는 사내 CA trust 배포
- Hostname 검증 HTTPS smoke test와 rollback

### 3. RBAC와 credential rotation

- 공용 admin 사용 현황 확인
- Admin, analyst, read-only 역할 분리
- Security_Team 운영 계정 mapping
- Credential Vault 관리와 break-glass runbook

### 4. AI shadow pipeline

- alerts.json read-only collector
- SQLite 또는 file 기반 durable offset/spool
- Canonical event schema와 allowlist redaction
- Event ID, correlation key, mock enrichment
- Fixture/unit test
- 외부 LLM과 notification은 event loss, duplicate, secret leakage 측정 후 활성화

## 다음 세션 시작 프롬프트

    최신 handoff는 docs/session-handoff-2026-07-04-wazuh-hardening.md에 있어.
    전체 verify-all, Wazuh custom detection fixture, platform hardening,
    30일 index retention과 일일 snapshot까지 적용 및 검증된 상태야.
    다음은 snapshot을 storage01로 외부 복제하고 restore test를 만든 뒤,
    dashboard certificate/RBAC를 정리하고 AI shadow pipeline 구현을 시작하자.

## 후속 완료 - Snapshot 외부 복제

- `storage01:/data/backups/wazuh-indexer`에 외부 replica 구성
- Wazuh IP의 NFSv4 TCP/2049만 UFW 허용
- `all_squash`, 전용 UID/GID 1900으로 원격 root 권한 차단
- 매일 03:15 KST 복제 timer와 36시간 freshness 검증 적용
- 외부 사본을 read-only OpenSearch repository로 등록해 SUCCESS snapshot 조회
- 정상 재실행 changed=0, 전체 verify-all failed=0/unreachable=0

남은 작업은 격리된 test indexer host를 준비한 뒤 실제 index restore/document count
검증을 자동화하는 것이다. 운영 cluster에는 restore test를 실행하지 않는다.

## 후속 완료 - Restore, Dashboard TLS, RBAC, AI shadow

- 외부 snapshot을 격리 OpenSearch cluster에 실제 restore하고 123 shard 성공 검증
- 월간 restore timer와 35일 stale 검증 적용
- Dashboard 전용 CA와 `wazuh.toss.lan`, `192.168.0.30`, `127.0.0.1` SAN 적용
- 전체 Linux 관리 호스트 CA trust 배포 및 실패 시 certificate rollback 검증
- `Security_Team` analyst, `Wazuh_ReadOnly` read-only SSO backend role mapping
- 내장 admin credential rotation과 Vault 기반 `sme_breakglass` 계정 검증
- read-only `alerts.json` collector, SQLite durable offset/spool, allowlist redaction,
  5분 deterministic correlation, mock enrichment의 AI shadow service 적용
- 외부 LLM, notification, automated action, network access는 비활성
- 전체 verify-all: 모든 host changed=0, failed=0, unreachable=0

다음 단계는 shadow 운영 지표를 일정 기간 측정한 뒤 event loss/duplicate/redaction
검증 결과를 바탕으로 notification 또는 외부 LLM 활성화 여부를 별도 승인하는 것이다.

## 최종 인계 기준

이 섹션이 다음 세션에서 사용할 최신 기준이다. 위의 `다음 계획` 1~4는 모두
완료됐으며 더 이상 미완료 작업이 아니다.

현재 운영 상태:

- Wazuh custom detection 7개 fixture 통과
- 30일 alert retention, 일일 local snapshot, storage01 외부 replica 적용
- 외부 replica 월간 실제 restore test 적용 및 123 shard 복원 성공
- Dashboard SAN 인증서와 내부 CA trust 적용
- `Security_Team` analyst, `Wazuh_ReadOnly` read-only RBAC 적용
- admin rotation 및 Vault 기반 `sme_breakglass` 적용
- AI shadow collector, SQLite spool, redaction, correlation, mock enrichment 적용
- 외부 LLM, notification, automated action은 비활성
- 전체 `verify-all`: 모든 host changed=0, failed=0, unreachable=0

주요 재실행 순서:

    cd /home/sysadmin/homelab-infra/ansible
    ansible-playbook -i inventory/hosts playbooks/wazuh-snapshot-replica.yml
    ansible-playbook -i inventory/hosts playbooks/wazuh-restore-test.yml
    ansible-playbook -i inventory/hosts playbooks/wazuh-dashboard-certificate.yml
    ansible-playbook -i inventory/hosts playbooks/wazuh-rbac.yml --vault-password-file .vault_pass
    ansible-playbook -i inventory/hosts playbooks/wazuh-ai-shadow.yml
    ansible-playbook -i inventory/hosts playbooks/verify-all.yml

다음 우선 작업:

1. AI shadow metrics를 며칠간 관찰한 뒤 notification 또는 외부 LLM 활성화 여부를
   별도 승인한다. 자동 대응은 계속 비활성 상태로 유지한다.
2. Terraform plan/apply가 필요할 때는 유효한 Proxmox API token을 먼저 주입하고,
   `terraform plan` 결과를 검토한 뒤 실행한다.

다음 세션 시작 프롬프트:

    최신 기준은 docs/session-handoff-2026-07-04-wazuh-hardening.md의
    '최종 인계 기준' 섹션이야. Wazuh restore/TLS/RBAC/AI shadow까지 완료됐고
    verify-all도 전부 통과했어. 먼저 Terraform state와 windows-test/Keycloak
    192.168.0.60 드리프트를 안전하게 조사하고, apply 전에 변경 계획을 보고해줘.

## 후속 완료 - 2026-07-04 Terraform drift와 AI shadow metrics

### Terraform windows-test/Keycloak drift

- 실제 `192.168.0.60` 호스트는 `keycloak`이며 `keycloak` service가 active임을 확인했다.
- 로컬 `terraform/terraform.tfvars`의 `windows-test` VM 정의를 `keycloak`으로 정정했다.
- Terraform state 주소를 `module.vm["windows-test"]`에서 `module.vm["keycloak"]`로 이동했다.
- `terraform state list` 기준 `windows-test`는 제거되고 `module.vm["keycloak"]`가 존재한다.
- `terraform apply`는 실행하지 않았다.
- `terraform plan -refresh=false -input=false`는 Proxmox provider token이 placeholder라 `401 invalid token value`로 실패했다. 유효한 token 주입 후 plan을 재확인해야 한다.
- Ansible common role의 core hosts mapping도 `192.168.0.60 keycloak.toss.lan keycloak`으로 수정했다.

### AI shadow metrics/report

- `wazuh_ai_shadow.py`에 SQLite metric counters와 JSON report 출력을 추가했다.
- report 필드: pending/enriched/total event count, seen/inserted/duplicate/invalid JSON count, duplicate rate, trim/backpressure indicators, redaction leakage count, p50/p95 enrichment latency.
- 기존 DB migration으로 `events.enriched_at` column을 추가한다. 기존 enriched event는 latency가 `null`일 수 있고 새 event부터 latency가 계산된다.
- `/var/lib/wazuh-ai-shadow/metrics.json` 생성과 safety 검증을 `wazuh-ai-shadow.yml`에 포함했다.
- 로컬 unit test 3개 통과, target unit test 통과, Wazuh 배포 성공.
- 배포 직후 report 기준: `events_total=5200`, `events_pending=0`, `redaction_leak_count=0`, `duplicate_rate=0.0`, loss indicators 0.
