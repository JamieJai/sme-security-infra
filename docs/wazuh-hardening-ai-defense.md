# Wazuh Hardening and AI Defense Design

이 문서는 현재 Wazuh 4.10 기반 수집 환경을 운영 수준으로 강화하고, 경보 요약과 분류를 위한 AI pipeline을 안전하게 연결하는 설계 기준이다.

## 설계 원칙

1. 탐지와 대응의 기준 데이터는 Wazuh 원본 alert다.
2. custom rule은 재현 가능한 fixture와 테스트를 먼저 만든다.
3. AI는 비동기 분석만 수행하며 Wazuh manager의 수집 경로를 막지 않는다.
4. AI 결과만으로 계정 잠금, 방화벽 차단, 파일 삭제를 실행하지 않는다.
5. 원본 로그의 secret, token, mail body, 개인 정보는 외부 모델에 보내지 않는다.
6. pipeline 장애 시 Wazuh 수집과 기존 경보는 계속 동작해야 한다.

## 현재 기준과 gap

현재 완료:

- 6개 managed host의 agent 등록과 Active 상태 확인
- AD, Nextcloud, Mail, Storage의 역할별 log source 설정
- Keycloak journald 수집
- 전체 verification playbook에서 manager service와 agent 상태 검증

보강 필요:

- manager/indexer/dashboard TLS, RBAC, secret 회전 기준
- installer checksum과 버전 upgrade 절차
- index retention, snapshot, disk watermark 정책
- custom decoder/rule의 Git 관리와 자동 테스트
- log source별 실제 event fixture와 탐지 품질 측정
- AI 분석용 최소 권한 export 경로와 redaction

## Wazuh hardening

### 배포와 공급망

- Wazuh 버전을 변수로 고정하고 manager와 agent 호환성을 검증한다.
- 원격 install script는 checksum을 고정하거나 package repository 기반 role로 교체한다.
- upgrade는 snapshot, staging 검증, manager, agent 순서로 진행한다.
- Wazuh repository key fingerprint와 package signature를 검증한다.

### 접근 통제

- dashboard는 관리 VLAN 또는 reverse proxy를 통해서만 노출한다.
- 관리자, analyst, read-only 역할을 분리하고 공용 admin 계정을 제거한다.
- API와 indexer credential은 Ansible Vault에 저장하고 정기 회전한다.
- dashboard, API, indexer 간 TLS 인증서 검증을 강제한다.
- SSH와 sudo 접근은 Security_Team 및 별도 break-glass 계정으로 제한한다.

### 데이터 보호와 가용성

- alert index retention은 가용 disk와 규제 요건에 맞춰 hot 30일을 초기 기준으로 둔다.
- 일별 snapshot과 월 1회 restore test를 수행한다.
- 70/80/90% disk 사용량에 warning, high, critical 경보를 둔다.
- alerts.json과 archive 사용 여부를 명시하고 불필요한 full archive는 끈다.
- manager configuration, local rules, decoders, certificates를 backup 대상에 포함한다.

### Agent와 수집

- enrollment source를 내부 subnet으로 제한하고 미등록 agent key를 주기적으로 제거한다.
- agent disconnect, duplicate name, queue overflow를 운영 경보로 만든다.
- log rotation 후에도 수집이 이어지는지 fixture와 통합 테스트로 확인한다.
- FIM은 OS baseline과 서비스 config에 집중하고 대용량 data/mail directory는 제외한다.
- rootcheck와 vulnerability detection 결과는 별도 운영 queue로 분류한다.

## Custom detection catalog

custom rule ID는 100100부터 100999 범위를 사용한다.

| ID 범위 | Source | 초기 탐지 |
|---|---|---|
| 100100-100199 | Nextcloud | login failure burst, admin change, public share, bulk download |
| 100200-100299 | Keycloak | LOGIN_ERROR burst, brute force lock, admin event, LDAP sync failure |
| 100300-100399 | Mail | SASL/IMAP auth failure burst, relay reject spike, mailbox anomaly |
| 100400-100499 | Samba AD | password spray, account lockout, privileged group change, replication failure |
| 100500-100599 | Storage/SMB | denied access burst, mass rename/delete, privileged share access |
| 100900-100999 | Platform | agent disconnect, queue pressure, disk/index health, pipeline failure |

각 rule은 redacted raw log fixture, expected decoder fields, expected rule ID와 level, false-positive 예외, MITRE mapping, owner와 대응 runbook을 함께 가진다. 배포 전 manager의 log test 도구로 positive fixture와 negative fixture를 모두 검증한다.

## AI defense pipeline

### Data flow

    Wazuh alerts.json
      -> local collector with durable offset
      -> bounded disk spool
      -> normalizer and redactor
      -> deterministic deduplication and severity gate
      -> AI enrichment worker
      -> case record and analyst notification

collector는 Wazuh host에서 read-only로 alert를 읽고, AI worker는 별도 service account와 network policy를 사용한다. 초기 구현은 polling 또는 file tail 기반으로 시작하며 manager process 안에 custom integration code를 넣지 않는다.

### Canonical event

필수 field:

- event_id: alert ID와 agent ID 기반의 안정적인 hash
- observed_at, received_at
- agent_id, agent_name, source_role
- rule_id, rule_level, rule_groups, mitre_ids
- actor, source_ip, target, action, outcome
- evidence: redacted field subset
- correlation_key
- schema_version

원본 full_log는 Wazuh에 남기고 AI payload에는 허용된 field만 포함한다.

### Deterministic stage

- event_id 기반 중복 제거
- rule level과 source별 routing
- 사용자, IP, 대상 기준 time-window correlation
- known scanner와 service account allowlist
- token, password, cookie, authorization header, mail body redaction
- payload 크기 제한과 control character 제거

### AI output contract

AI 응답은 JSON schema로 검증하며 verdict, confidence, summary, evidence_refs, hypotheses, recommended_actions, escalation_required, model, prompt_version, generated_at을 포함한다.

근거가 없는 actor, IP, host를 새로 만들지 못하게 하고 evidence_refs가 입력 event field를 참조하는지 검증한다. schema 실패, timeout, rate limit은 unknown으로 기록하고 retry queue로 보낸다.

### Prompt injection과 모델 경계

- log text는 명령이 아닌 untrusted data로 구분한다.
- log 안의 지시문, URL, encoded payload를 실행하거나 조회하지 않는다.
- AI worker에는 shell, SSH, Wazuh write API, identity admin API 권한을 주지 않는다.
- 외부 모델 사용 시 redacted payload만 보내고 retention 비활성화 조건을 확인한다.
- prompt와 model 변경은 versioned evaluation set을 통과해야 배포한다.

### Response policy

초기 단계는 analyst notification만 허용한다. 자동 대응은 AI verdict가 아니라 deterministic rule, 명시적 allowlist, 승인된 playbook을 모두 만족할 때 별도 단계에서 검토한다.

| Severity | 처리 |
|---|---|
| Low | 저장 및 dashboard 표시 |
| Medium | AI 요약, 업무 시간 digest |
| High | AI 요약, 즉시 Security_Team 통지, analyst 확인 |
| Critical | 즉시 통지, 기존 수동 incident runbook 시작 |

## 구현 단계

### Phase 1: Detection foundation

- custom decoder/rule 디렉터리와 Ansible 배포 playbook
- Nextcloud, Keycloak, Mail, AD fixture 수집 및 redaction
- positive/negative rule test runner
- agent disconnect와 index disk 경보

완료 기준: 핵심 4개 source별 최소 2개 rule, fixture test 100% 통과, 기존 alert volume 회귀 없음.

### Phase 2: Wazuh platform hardening

- package/version/checksum 기준
- dashboard/API/indexer TLS와 RBAC
- Vault secret 회전
- retention, snapshot, restore test

완료 기준: admin 공유 계정 없음, 평문 credential 없음, restore test 성공, verification runbook에 health check 포함.

### Phase 3: AI shadow mode

- collector, spool, normalizer, redactor 구현
- JSON schema 기반 AI enrichment
- 2주간 notification 없이 shadow evaluation
- precision, unknown rate, latency, token cost 측정

완료 기준: event loss 0, duplicate 1% 미만, p95 처리 시간 목표 충족, secret leakage test 0건.

### Phase 4: Analyst notification

- High/Critical alert만 Security_Team channel로 전달
- feedback label과 case audit trail 저장
- weekly false-positive review와 rule tuning

자동 차단은 이 단계의 범위가 아니다.

## 검증 지표

- source별 event ingest rate와 last-event age
- decoder success rate
- rule별 alert count와 false-positive rate
- agent disconnect duration
- collector lag, spool depth, dropped event count
- redaction test pass rate
- AI schema failure, unknown, timeout 비율
- analyst verdict agreement와 mean time to acknowledge

## 다음 구현 단위

첫 구현은 AI service보다 custom rule test harness를 먼저 만든다. 실제 fixture가 안정되어야 canonical schema와 AI evaluation set도 신뢰할 수 있다.

## 구현된 shadow collector

`wazuh-ai-shadow.yml`은 `/var/ossec/logs/alerts/alerts.json`을 read-only로 읽는
`wazuh-ai-shadow` 계정을 배포한다. SQLite WAL spool에 inode/byte offset과 event ID를
저장해 중복과 rotation을 처리하며 최대 10,000건으로 제한한다. canonical event에는
allowlist field만 저장하고 full_log, password, token, cookie, authorization, body는
저장하지 않는다. 현재 enrichment는 5분 correlation과 severity를 계산하는
`deterministic-v1`이며 notification과 automated_action은 항상 false다. 외부 LLM,
network access, Wazuh write API, SSH/shell 권한은 없다.
