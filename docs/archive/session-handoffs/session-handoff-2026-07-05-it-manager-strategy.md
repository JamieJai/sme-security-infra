# Session Handoff - 2026-07-05 IT Manager Strategy

이 문서는 `homelab-infra` 프로젝트의 방향성을 토스 IT Manager 포지션 준비에 맞춰 전환하기 위한 전략 handoff다. 다음 세션에서는 이 문서를 먼저 읽고 바로 실행 계획을 이어간다.

## 오늘 완료한 주요 작업

### 인프라 정상화 및 자동화

- `scripts/ansible-baseline.sh` 추가 및 실제 적용 검증 완료.
- `scripts/ansible-services.sh` 추가 및 실제 적용 검증 완료.
- `scripts/verify-all.sh` 추가 및 최종 검증 완료.
- `scripts/full-check.sh` 추가.
  - Terraform plan + 전체 verify 비파괴 검증 경로.
- `scripts/full-apply.sh` 추가.
  - Terraform apply, Ansible baseline, services, verify를 단계별 confirm으로 실행.
  - `RUN_AGENT_DEPLOY=false` 기본값.
- `scripts/ansible-agent-deploy.sh` 추가.
  - Wazuh agent 설치/재배포 전용.

검증 결과:

```text
scripts/ansible-services.sh: failed=0, unreachable=0
scripts/verify-all.sh: failed=0, unreachable=0
scripts/full-check.sh: Terraform No changes + verify 통과
```

### AD DNS 및 apt repository 고도화

- Samba AD DNS forwarder를 IaC로 관리.
- AD DNS A/PTR/CNAME 관리 확장.
  - CNAME: `mail -> mail01`, `autoconfig -> mail01`, `keycloak-ldap-ha -> keycloak`
  - PTR: core host 전체.
- `verify-all.yml`에 DNS forwarder, A, PTR, CNAME 검증 추가.
- Wazuh apt repository를 legacy `apt_key`에서 `signed-by=/usr/share/keyrings/wazuh.gpg`로 이전.
- Grafana apt repository를 `signed-by=/etc/apt/keyrings/grafana.asc`로 이전.
- 전체 호스트 apt update에서 `legacy trusted.gpg` 경고 제거 확인.

### 문서 구조 정리

문서를 역할별 디렉터리로 재구성했다.

```text
docs/
  README.md
  architecture.md
  getting-started/
  operations/
  reference/
  services/
  recovery/
  archive/session-handoffs/
```

- `docs/README.md`를 새 문서 시작점으로 추가.
- session handoff 문서는 `docs/archive/session-handoffs/`로 이동.
- 주요 문서 제목을 한국어 중심으로 정리.
- 이전 `docs/*.md` 루트 링크를 새 위치로 보정.

## 진로 전략 결정

두 포지션을 비교했다.

### 토스 IT Manager

현재 프로젝트와 직접 맞는 부분이 많다.

- AD, Keycloak, OIDC, LDAP, LDAPS
- 계정/권한/그룹 관리
- Nextcloud, Mail, DNS, 인증서
- Wazuh agent와 로그 수집
- Terraform/Ansible 자동화
- `full-check`, `verify-all`, `full-apply` 같은 운영 검증 구조
- 장애/반복 문제를 자동화와 runbook으로 줄이는 흐름

부족한 부분:

- Windows/macOS 단말 관리
- Okta/SaaS 운영 경험
- 헬프티켓 기반 문제 해결 사례
- 사용자 경험 중심 문서/가이드
- 데이터 기반 반복 문제 제거 사례

### 토스인컴 Security Engineer

현재 프로젝트와 맞는 보안 요소도 있지만, 다음 축이 아직 부족하다.

- AWS 클라우드 보안 아키텍처
- 클라우드 위협 탐지/대응
- DB 보안
- 망분리/정보유출 대응 체계
- ISO27001, ISO27701, ISMS-P 대응 경험
- 실제 위협 대응 사례

결론:

```text
단기 집중 목표: 토스 IT Manager
중기 확장 목표: Security Engineer로 확장 가능한 보안 포트폴리오
```

## 앞으로의 프로젝트 방향성

이 프로젝트는 앞으로 단순 homelab이 아니라 `사내 IT 업무 환경 운영 플랫폼` 포트폴리오로 고도화한다.

핵심 문장:

> 임직원이 기술 장벽 없이 일할 수 있도록 계정, 메일, 협업도구, 파일 공유, 보안 로그, 장애 대응을 자동화하고 표준화한 사내 IT 운영 환경

## IT Manager 중심 고도화 로드맵

### 1. 입사/퇴사 자동화

목표: 신규 입사자와 퇴사자 처리를 표준화하고 자동 검증한다.

구현 후보:

- 신규 입사자 AD 계정 생성
- 부서별 그룹 자동 부여
- Keycloak LDAP sync 확인
- Nextcloud 그룹/스토리지 접근 확인
- Mail address 속성 확인
- 퇴사자 계정 disable
- 그룹/권한 회수
- 온보딩/오프보딩 결과 리포트 생성

다음 세션 1순위 작업:

```text
신규 입사자 온보딩 자동화 v1
```

우선 읽을 파일:

```text
ansible/playbooks/ad-onboard-user.yml
docs/reference/ansible-playbook-catalog.md
docs/operations/operation-modes.md
```

### 2. 헬프티켓 시나리오화

IT Manager 이력서에는 기술 자체보다 문제 해결 사례가 중요하다.

시나리오 후보:

- 메일 로그인이 안 된다.
- Nextcloud 부서 폴더가 안 보인다.
- SSO 로그인이 실패한다.
- 권한이 잘못 부여됐다.
- 신규 입사자 계정 생성 후 일부 서비스 접근이 안 된다.

각 시나리오는 다음 형식으로 문서화한다.

```text
문제
영향
원인
임시 조치
근본 해결
자동화/검증
재발 방지
```

추천 문서 위치:

```text
docs/operations/helpdesk-scenarios.md
```

### 3. 사용자 온보딩 문서

비전문가가 읽을 수 있는 문서를 만든다.

후보 문서:

```text
docs/getting-started/employee-it-onboarding.md
```

포함 내용:

- SSO 로그인 방법
- 메일 사용 방법
- Nextcloud 사용 방법
- 부서별 공유 폴더 접근 기준
- 비밀번호/보안 정책
- 문제가 생겼을 때 요청해야 하는 정보

### 4. 단말 관리 미니랩

토스 IT Manager 공고에서 Windows/macOS 이해를 요구하므로 별도 미니랩이 필요하다.

macOS 후보:

- FileVault 상태 확인 shell script
- hostname 확인
- 필수 앱 설치 여부 확인
- 보안 설정 점검

Windows 후보:

- BitLocker 상태 확인 PowerShell
- Defender 상태 확인
- 로컬 관리자 계정 확인
- 필수 앱 설치 여부 확인

추천 위치:

```text
endpoint/
  macos/
  windows/
docs/services/endpoint-management.md
```

### 5. SaaS/Okta 운영 시뮬레이션

현재 Keycloak/AD 경험은 좋지만, Okta/SaaS 운영 언어로 번역해야 한다.

보강 후보:

- Okta 무료/개발자 환경 조사
- SSO, SCIM, JIT provisioning 개념 정리
- Google Workspace, Slack, Notion, Jira 온보딩/오프보딩 정책 문서화

추천 문서:

```text
docs/services/saas-identity-operations.md
```

### 6. 운영 리포트/대시보드

IT 문제를 데이터화했다는 근거를 만든다.

후보 지표:

- 계정 현황
- 그룹/권한 현황
- Wazuh agent 상태
- 실패 로그인
- 인증서 만료
- 백업 상태
- `verify-all` 결과
- 온보딩/오프보딩 성공 여부

후보 구현:

```text
scripts/report-it-health.sh
reports/
```

## 다음 세션 실행 계획

다음 세션에서는 바로 아래 순서로 진행한다.

1. `docs/archive/session-handoffs/session-handoff-2026-07-05-it-manager-strategy.md` 읽기.
2. `ansible/playbooks/ad-onboard-user.yml` 분석.
3. 신규 입사자 온보딩 자동화 v1 설계.
4. 필요한 변수/입력 형식 결정.
5. 온보딩 실행 후 검증 리포트 구조 설계.
6. 가능하면 다음 파일 추가:
   - `docs/operations/employee-lifecycle-runbook.md`
   - `docs/getting-started/employee-it-onboarding.md`
   - `scripts/onboard-user.sh` 또는 Ansible wrapper

## 남은 기술 개선 후보

- `ansible-services.sh` 반복 실행 시 일부 Keycloak/Nextcloud task가 매번 `changed`로 표시된다.
- 기능 검증은 통과하지만 idempotency 개선 여지가 있다.
- 우선순위는 낮다. IT Manager 포트폴리오 관점에서는 먼저 온보딩/헬프티켓 시나리오가 더 중요하다.

## 커밋 상태

오늘 주요 작업은 다음 커밋으로 push 완료했다.

```text
7d31b89 Normalize infra automation and reorganize docs
origin/main
```
