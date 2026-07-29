# IT Manager Portfolio Demo Runbook

이 runbook은 저장소 검토자에게 10분 안에 프로젝트의 핵심을 설명하기 위한
비파괴 데모 순서다. 기본 경로는 live infrastructure, password, Vault, token을
요구하지 않는다.

## 0. 시작 전 설명

먼저 다음 범위를 명확히 밝힌다.

- 개인 Proxmox homelab에서 수행한 IT 운영 시뮬레이션이다.
- test identity와 test endpoint만 사용했다.
- 회사 production 운영, 실제 임직원 SLA, macOS/Google Workspace 경험으로
  과장하지 않는다.

## 1. 1분: 문제 정의

설명:

> 계정, PC, 협업 도구, 보안 로그를 각각 설치하는 것이 아니라 입사자가 업무를
> 시작하고 장애 발생 시 운영자가 원인을 확인할 수 있는 workflow를 만들었습니다.

보여줄 문서:

- `README.md`
- `docs/architecture.md`

## 2. 2분: 온보딩 workflow

```bash
./scripts/onboard-employee.sh --help
sed -n '50,165p' docs/operations/employee-onboarding-runbook.md
```

강조할 내용:

- password를 CLI option으로 받지 않음
- AD 생성 뒤 Keycloak/Nextcloud/Mail/Wazuh까지 검증
- `success`, `partial`, `failed` 구분
- 자동 삭제보다 조사 가능한 report를 우선

실제 계정 생성은 demo 기본 범위에 포함하지 않는다.

## 3. 2분: 사용자 문의와 자산을 운영 workflow로 바꾸기

로컬 임시 경로와 임시 SQLite DB만 사용해 endpoint 등록·지급, SSO 티켓,
triage, KPI, 오프보딩 plan을 재현한다. live inventory에는 접속하지 않는다.

```bash
demo_dir="$(mktemp -d /tmp/it-manager-demo.XXXXXX)"
DEMO_DIR="$demo_dir" ./scripts/it-manager-demo.sh
```

생성된 SQLite와 Markdown에서 다음을 확인한다.

- endpoint `registered → in_stock → assigned` 이력
- ticket `open → first response → resolved` event와 `simulation` 분류
- priority별 response/resolution SLA report
- read-only 진단 계획과 asset context
- 오프보딩 plan이 assigned asset을 식별하지만 상태를 바꾸지 않음

`--execute`는 live lab owner가 read-only Ansible 진단을 수행할 때만 사용한다.

## 4. 1분: 승인과 상태 전이 설명

통합 데모가 생성한 자산 report와 runbook을 연다.

```bash
sed -n '1,180p' docs/operations/asset-lifecycle-runbook.md
```

강조할 내용:

- 자산 execute에는 ticket, approver, expected status, exact asset 확인이 필요하다.
- wipe 완료와 폐기에는 evidence reference가 필요하다.
- 오프보딩 plan에서는 AD, Keycloak, Nextcloud와 asset status가 바뀌지 않는다.
- 오프보딩 execute에는 ticket, approver, exact username confirmation이 필요하다.
- 삭제 대신 disable-first와 별도 recovery 절차를 사용한다.
- live 결과와 중간 실패는
  `docs/portfolio/employee-offboarding-lifecycle-pilot.md`에서 확인한다.

## 5. 2분: 관리자 권한 없는 앱 배포

```bash
sed -n '254,307p' docs/portfolio/endpoint-app-deployment-system-install.md
```

설명 순서:

1. local admin 제공이 빠르지만 권한 경계를 무너뜨리는 이유
2. 사용자 share와 computer installer share를 분리한 이유
3. SYSTEM context와 pilot group을 선택한 이유
4. reboot와 idempotency까지 검증한 이유

## 6. 2분: 실패를 숨기지 않는 Wazuh 운영

```bash
sed -n '166,218p' \
  docs/archive/session-handoffs/session-handoff-2026-07-28-kali-egress-enabled.md
```

설명 순서:

1. shared backup filename 때문에 Windows sync가 실패함
2. backup을 보존하면서 sync directory 밖으로 이동함
3. manager active만으로는 receiver 정상 여부를 알 수 없었음
4. TCP 1514와 전체 agent Active를 성공 조건에 추가함

핵심은 장애가 없었다는 주장이 아니라 장애를 관찰하고 성공 기준을 개선했다는
점이다.

## 7. 1분: 저장소 자체 검증

```bash
./scripts/portfolio-check.sh
```

검증 항목:

- 지원 핵심 문서가 Git tracking 대상인지 확인
- secret guard 실행
- 주요 shell syntax
- 비파괴 IT Manager 통합 demo
- Helpdesk ticket/KPI와 asset lifecycle 단위 테스트
- 오프보딩 plan 비변경성과 execute safety gate
- Kali egress guard unit test
- Wazuh XML parse
- 핵심 Ansible playbook syntax

## Live Lab 선택 검증

아래 명령은 저장소 검토자가 아니라 secret과 inventory를 가진 lab owner만
실행한다.

```bash
./scripts/verify-and-report.sh
```

이 명령은 전체 verification 결과를 Markdown과 SQLite에 기록하고, 설정된
경우에만 Slack/Notion으로 요약을 전송한다. 실패 시 자동 복구나 계정 삭제를
수행하지 않는다.
