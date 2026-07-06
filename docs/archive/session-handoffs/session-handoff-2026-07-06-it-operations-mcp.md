# Session Handoff - 2026-07-06 IT Operations MCP

이 문서는 `homelab-infra`를 단순 IaC 실습 repo가 아니라 AI/MCP 기반 IT 운영 업무 플랫폼으로 전환하는 작업의 handoff다. 다음 세션에서는 이 문서를 먼저 읽고 `신입사원 온보딩 v1` workflow 구현부터 이어간다.

## 이번 세션의 방향 전환

프로젝트 기준을 다음처럼 재정의했다.

```text
AI에게 코드 작성을 시키는 프로젝트가 아니라,
AI에게 실제 IT 운영 업무를 맡기는 프로젝트로 만든다.
```

대표 목표 workflow:

```text
"신입사원 김철수를 IT팀으로 온보딩해."
```

Codex/AI가 수행해야 할 이상적인 흐름:

1. GitHub/Git 상태 확인 및 feature branch 준비
2. Filesystem에서 기존 playbook/script/runbook 읽기
3. AD 사용자 생성 및 부서 그룹 부여
4. Keycloak LDAP sync / OIDC 흐름 확인
5. Nextcloud 그룹, 부서 스토리지, Mail 연동 확인
6. Ansible/verify 실행
7. SQLite 운영 DB에 결과 기록
8. Markdown 검증 리포트 생성
9. Slack/Jira/GitHub 알림 또는 티켓/PR 생성
10. 변경이 있으면 commit/PR 준비

면접/포트폴리오 핵심 문장:

```text
AI와 MCP를 활용해 입사자 온보딩부터 검증, 보고, 문서화까지 자동화된 IT 운영 워크플로를 구축했습니다.
```

## 이번 세션에서 추가/변경한 것

### MCP 및 Codex 운영 기준

- `AGENTS.md` 추가
  - Codex가 이 repo를 IT 운영 플랫폼으로 다룰 때 지켜야 할 원칙을 기록했다.
  - Prior Check, Idempotency, Documentation, Safety First, GitOps, Verification, Secrets 기준 포함.

- `.codex/config.toml` 추가
  - 프로젝트 MCP 설정을 기록했다.

- `~/.codex/config.toml`에도 MCP 설정을 병합했다.
  - 현재 `codex mcp list` 기준으로 MCP가 실제로 보인다.

### MCP roadmap 문서

- `docs/operations/mcp-roadmap.md` 추가
  - Filesystem, GitHub/GitOps, SQLite DB, Slack, Jira, Playwright, Docker, Proxmox 우선순위 정리.
  - Employee Onboarding 운영 workflow 정리.
  - 필요한 환경변수와 safety rule 정리.

- `docs/README.md`에 MCP roadmap 링크 추가.

### Homelab 전용 MCP 서버

- `.codex/mcp/homelab_mcp.py` 추가/확장.
- 현재 제공하는 주요 도구:
  - Filesystem: `project_tree`, `read_project_file`, `write_project_file`
  - GitOps: `git_status`, `git_create_branch`, `git_commit_all`
  - GitHub REST: `github_create_issue`, `github_create_pull_request`
  - SQLite: `ops_db_record_verify_result`, `ops_db_recent_verify_results`, `ops_db_upsert_asset`, `ops_db_assets`
  - Slack: `slack_notify`
  - Jira: `jira_create_issue`
  - Docker: `docker_ps`, `docker_logs`, `docker_restart`
  - Proxmox: `proxmox_vms`, `proxmox_node_status`
  - Existing infra helpers: Ansible inventory/hosts, playbook syntax check, Terraform state list/validate, service health, Wazuh/Nextcloud/Keycloak helpers.

## 현재 MCP 상태

`codex mcp list` 기준:

```text
enabled:
- homelab
- ansible_homelab
- trivy
- playwright
- context7
- openaiDeveloperDocs

disabled:
- github
```

`github` MCP는 Docker 기반으로 설정했지만 현재 host에 Docker CLI가 없어 disabled 상태로 둔 것이 맞다. GitHub 작업은 당분간 `homelab` MCP의 REST helper 또는 일반 git/SSH 기반으로 처리한다.

## 현재 worktree 상태

마지막 확인 기준:

```text
 M docs/README.md
?? .codex/
?? AGENTS.md
?? docs/operations/mcp-roadmap.md
```

아직 commit하지 않았다. 다음 세션에서 이어서 작업한 뒤 한 번에 commit해도 된다.

## 검증한 것

아래는 통과했다.

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/ad-onboard-user.yml --syntax-check
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-all.yml --syntax-check
/home/sysadmin/ai-cli/venv/bin/python -m py_compile .codex/mcp/homelab_mcp.py
codex mcp list
```

주의: MCP tool 목록은 새 Codex 세션을 시작해야 실제 도구로 주입될 수 있다.

## 현재 인프라 준비도 평가

### 이미 강한 부분

- Terraform/Ansible 기반 인프라 구조가 있다.
- AD, Keycloak, Nextcloud, Mail, Wazuh, Storage, DNS, Backup, Certificate monitor가 구성되어 있다.
- `verify-all.yml`은 단순 ping 수준이 아니라 AD replication, FSMO, DNS, Keycloak, Nextcloud, Mail, Wazuh snapshot/restore/RBAC/AI shadow까지 꽤 깊게 본다.
- `scripts/full-check.sh`, `scripts/full-apply.sh`, `scripts/verify-all.sh`가 있어 전체 점검/적용 루틴이 있다.

### 아직 부족한 부분

가장 큰 부족분은 인프라 자체보다 `업무 단위 orchestration layer`다.

현재는 다음이 각각 분리되어 있다.

- AD 사용자 생성: `ansible/playbooks/ad-onboard-user.yml`
- 전체 검증: `scripts/verify-all.sh`, `ansible/playbooks/verify-all.yml`
- MCP SQLite 기록 도구
- Slack/Jira/GitHub helper
- 문서/runbook

하지만 아직 아래처럼 하나의 업무 요청으로 묶이지 않았다.

```text
employee_onboarding_request
  -> AD 생성
  -> 그룹 부여
  -> Keycloak/Nextcloud/Mail 검증
  -> 리포트 생성
  -> SQLite 기록
  -> Slack/Jira/GitHub 알림
```

## 다음에 바로 할 일: 신입사원 온보딩 v1

다음 세션의 1순위 작업은 `신입사원 온보딩 v1` workflow를 구현하는 것이다.

추천 구현 순서:

1. `docs/operations/employee-onboarding-runbook.md` 추가
   - 요청 입력값
   - 부서별 그룹 매핑
   - 실행 명령
   - 검증 항목
   - 실패 시 복구 절차
   - 리포트 위치

2. `scripts/onboard-employee.sh` 추가
   - 입력값: username, given name, surname, email, department, temporary password
   - 내부에서 `ad-onboard-user.yml` 실행
   - 부서 -> AD group mapping 적용
   - 실행 log를 `artifacts/onboarding/`에 저장

3. 온보딩 검증 playbook 추가 또는 기존 playbook 확장
   - 후보: `ansible/playbooks/employee-onboarding-verify.yml`
   - 검증 항목:
     - AD user exists
     - AD mail attribute exists
     - expected AD groups contain user
     - Keycloak realm/LDAP federation reachable
     - Nextcloud expected groups/storage still valid
     - Mail domain and service reachable

4. 리포트 생성 추가
   - `artifacts/onboarding/<timestamp>-<username>.md`
   - 포함 내용:
     - 요청자/대상자/부서
     - 실행 playbook
     - 변경 여부
     - 검증 결과
     - 후속 수동 작업

5. SQLite 기록 연결
   - 우선 간단히 Python 또는 MCP helper를 사용해서 onboarding result를 `.codex/mcp/homelab_ops.sqlite`에 기록.
   - 나중에 `operations` table을 onboarding/offboarding 전용으로 확장해도 된다.

6. Slack 알림 연결
   - `SLACK_WEBHOOK_URL`이 있으면 완료/실패 알림.
   - 없으면 skip하고 리포트에 `notification skipped` 기록.

7. GitOps 마감
   - 변경 파일 확인
   - commit message 예: `Add employee onboarding operations workflow`
   - PR body에는 runbook, 검증, 남은 수동 작업 명시.

## 온보딩 v1에서 너무 욕심내지 말 것

v1에서는 실제 브라우저 로그인이나 비밀번호 전달 자동화까지 넣지 않아도 된다.

우선 목표는 다음 수준이면 충분하다.

```text
AD 계정 생성 + 그룹 부여 + 핵심 identity/storage/mail 검증 + 리포트 + DB 기록
```

Playwright E2E, Jira ticket 자동화, GitHub PR 자동 생성은 v2로 미뤄도 된다.

## 이후 확장 순서

1. Employee Offboarding workflow
2. `verify-and-report.sh`
   - 전체 검증 실행
   - markdown summary 생성
   - SQLite 기록
   - Slack 알림
3. Playwright E2E
   - Keycloak admin reachable
   - Nextcloud OIDC login flow
4. Helpdesk scenarios
   - `docs/operations/helpdesk-scenarios.md`
   - Mail login fail, SSO fail, Nextcloud folder missing, permission mismatch
5. Docker/GitHub MCP hardening
   - Docker CLI 설치 또는 GitHub MCP 대체 경로 결정
   - official GitHub MCP enable 여부 판단

## 중요한 주의점

- `terraform.tfstate`, `terraform.tfvars`, vault 값, API token, Slack webhook, Jira token은 절대 commit하지 않는다.
- 실제 운영 변경은 승인 없이 실행하지 않는다.
- `full-apply.sh`, destructive playbook, account disable/delete, Docker restart, Proxmox power/snapshot action은 모두 승인 대상이다.
- 현재 `docker` CLI는 host에 없다.
- `playwright`와 `context7`는 `npx` 기반이라 첫 실행 시 network/npm download가 필요할 수 있다.
- 새 MCP 설정은 새 Codex 세션에서 가장 확실하게 반영된다.
