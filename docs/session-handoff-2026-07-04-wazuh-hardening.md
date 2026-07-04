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
