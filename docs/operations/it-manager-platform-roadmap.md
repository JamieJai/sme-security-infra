# IT Manager Platform Roadmap

이 프로젝트의 방향성은 단순한 homelab IaC가 아니라, AI/MCP가 실제 사내 IT 운영 업무를 보조하는 플랫폼이다. 핵심은 계정, 권한, 협업도구, 파일 공유, 메일, 보안 로그, 장애 대응을 업무 단위 workflow로 묶고 증적을 남기는 것이다.

## 역할 분리

| 영역 | 도구 | 역할 |
|---|---|---|
| Identity | AD, Keycloak, LDAP/OIDC | 계정, 그룹, SSO, 접근 제어의 기준 |
| Collaboration | Nextcloud, Nextcloud Talk, Mail | 파일 공유, 웹 메신저, 메일 업무 환경 |
| Endpoint | Windows AD Join package, future macOS checks | 신규 PC 도메인 가입, 기본 보안 설정, 사용자 셀프서비스 |
| Operations alerts | Slack | 온보딩 완료, 검증 실패, 인증서/백업/Wazuh 경보 같은 공통 운영 알림 |
| Knowledge base | Notion | 승인된 runbook, 온보딩 리포트, 장애 회고, 주간 IT health report 보관 |
| Helpdesk | Jira/GitHub Issues | 사용자 요청, 장애 티켓, 재발 방지 task 추적 |
| Evidence store | SQLite, Markdown artifacts | 자동화 실행 결과와 감사 증적 저장 |
| Security visibility | Wazuh | 인증/메일/Nextcloud/AD 로그 기반 탐지와 대응 근거 |

## 현재 상태

- 신규 입사자 온보딩 v1은 AD 계정 생성, 부서 그룹 부여, Keycloak/Nextcloud/Mail/Wazuh 검증, Markdown 리포트, SQLite 기록, 선택적 Slack 알림까지 구현됐다.
- 사내 메신저는 Nextcloud Talk 웹 앱으로 구현돼 있다. `ansible/playbooks/nextcloud-talk.yml`이 설치/활성화를 담당하고, `verify-all.yml`은 `mail`과 `spreed` 앱 활성 상태를 같이 검증한다.
- Slack은 `SLACK_WEBHOOK_URL` 기반으로 온보딩 결과 알림을 보낼 수 있다. 다음 단계는 온보딩 외 verify, backup, certificate, Wazuh 이벤트까지 공통 알림으로 확장하는 것이다.
- Notion은 `homelab` MCP의 `notion_create_page`, `notion_publish_project_file` helper를 통해 운영 문서를 publish할 수 있게 한다. 토큰과 부모 페이지 ID는 env var로만 주입한다.

## 운영 workflow 목표

### 1. Employee onboarding

1. 요청 입력 검증
2. AD 계정 생성 및 그룹 부여
3. Keycloak/Nextcloud/Mail/Wazuh baseline 검증
4. Markdown report 생성
5. SQLite operations record 저장
6. Slack 알림
7. 승인된 report 또는 runbook을 Notion에 publish
8. GitOps commit/PR 준비

### 2. IT health report

1. `verify-all.yml` 또는 전용 report script 실행
2. 실패/경고 항목 요약
3. SQLite에 `it_health` 결과 기록
4. Slack `#it-ops` 성격의 공통 채널에 요약 발송
5. Markdown report를 `reports/`에 저장
6. 필요 시 Notion 운영 페이지에 publish

### 3. Helpdesk scenario

1. 사용자 증상 접수: 메일 로그인 실패, SSO 실패, 부서 폴더 미노출, 권한 오류
2. 해당 runbook에 맞춰 read-only 진단
3. 원인/영향/임시 조치/근본 조치 기록
4. Jira/GitHub issue 생성 또는 갱신
5. 해결 후 Slack 알림과 Notion 회고 문서 publish


### 4. Endpoint self-service

1. 온보딩 포털 또는 제한된 공유 경로에서 사번 기반 Windows AD Join package 제공
2. package는 secret을 포함하지 않고, 실행 시 AD credential을 입력받음
3. DNS 설정/검증, domain join, reboot를 PowerShell script로 표준화
4. v2에서는 Offline Domain Join blob으로 credential 입력 부담을 줄임
5. 실행 결과를 IT health/reporting workflow와 연결

## 우선순위

1. `verify-and-report.sh` 추가: 전체 검증, Markdown summary, SQLite 기록, Slack 알림, 선택적 Notion publish.
2. Windows AD Join 셀프서비스 v1: 사번 기반 no-secret package 생성, 사용자 가이드, 향후 Offline Domain Join 설계.
3. `docs/operations/helpdesk-scenarios.md` 추가: IT Manager 면접용 문제 해결 사례 구조화.
4. `docs/getting-started/employee-it-onboarding.md` 추가: 비전문가용 SSO, Mail, Nextcloud, Talk 사용 가이드.
5. Nextcloud Talk 운영 보강: 사용자 가이드, 알림 정책, TURN 서버 필요성 판단, 모바일 사용 범위 정리.
6. Notion 운영 페이지 템플릿 정의: Runbook, Incident Review, Weekly IT Health, Employee Onboarding Report.
7. Slack 알림 taxonomy 정의: `success`, `partial`, `failed`, `attention_required` 같은 상태와 메시지 포맷 통일.

## Notion MCP 운영 기준

필수 env var:

```text
NOTION_TOKEN
NOTION_PARENT_PAGE_ID
```

원칙:

- Notion에는 secret, 임시 비밀번호, vault 값, token, webhook URL을 쓰지 않는다.
- 자동 publish는 Markdown report와 runbook처럼 승인 가능한 산출물에 한정한다.
- 장애 조사 중 raw log 전체를 올리지 않고, redacted summary와 관련 artifact path만 남긴다.

## Slack 운영 기준

필수 env var:

```text
SLACK_WEBHOOK_URL
```

권장 알림 대상:

- 신규 입사자 온보딩 완료/부분 성공/실패
- `verify-all` 실패
- 인증서 만료 임박
- 백업 실패 또는 restore test 실패
- Wazuh critical/high alert summary

Slack은 실시간 공통 알림, Notion은 승인된 문서와 지식 축적, Nextcloud Talk는 내부 사용자 커뮤니케이션으로 분리한다.
