# Employee Onboarding Runbook

이 runbook은 신규 입사자를 AD, Keycloak, Nextcloud, Mail 운영 흐름에 편입하는 표준 절차다. 목표는 사람이 수동으로 여러 시스템을 확인하는 대신, Codex/MCP와 Ansible이 요청 접수부터 검증, 리포트, 기록까지 일관되게 수행하게 만드는 것이다.

## Scope

v1 범위:

- AD 사용자 생성 또는 기존 사용자 보정
- 부서 기준 AD group 부여
- mail attribute 설정
- Keycloak/Nextcloud/Mail 기본 검증
- 실행 로그와 Markdown 리포트 생성
- SQLite 운영 DB 기록
- Slack 알림은 `SLACK_WEBHOOK_URL`이 있을 때만 전송

v1에서 제외:

- 임시 비밀번호 전달 자동화
- 실제 브라우저 기반 OIDC login E2E
- Jira ticket 자동 상태 변경
- GitHub PR 자동 생성
- 계정 offboarding은 별도
  [Employee Offboarding Runbook](employee-offboarding-runbook.md)에서 처리

## Required Inputs

| Field | Example | Notes |
|---|---|---|
| `username` | `kim.chulsoo` | AD `sAMAccountName` 기준. 공백 없이 소문자 권장 |
| `given_name` | `Chulsoo` | AD given-name |
| `surname` | `Kim` | AD surname |
| `email` | `kim.chulsoo@toss.lan` | Mail attribute |
| `department` | `IT` | 아래 department mapping 중 하나 |
| `temporary_password` | secret | CLI history와 log에 남기지 않는 입력 방식 필요 |
| `must_change_password` | `true` | 첫 로그인 시 변경 강제 여부 |

## Department Mapping

현재 `ansible/group_vars/all.yml` 기준 부서 그룹은 다음과 같다.

| Department | AD group | Nextcloud mount |
|---|---|---|
| `HR` | `HR_Staff` | `/HR` |
| `Finance` | `Finance_Staff` | `/Finance` |
| `IT` | `IT_Admins` | `/IT` |
| `Security` | `Security_Team` | `/Security` |

`department` 값은 반드시 위 표 중 하나여야 한다. 새 부서가 생기면 `nextcloud_oidc_department_groups`, `nextcloud_department_storage`, 이 runbook, 그리고 검증 playbook을 같이 갱신한다.

## Wrapper Command v1

표준 실행 경로는 `scripts/onboard-employee.sh`다. wrapper는 AD 적용, 온보딩 전용 검증, 핵심 서비스 baseline 검증, Markdown 리포트 생성, SQLite 기록, 선택적 Slack 알림을 한 번에 수행한다. 실제 비밀번호는 shell history와 log에 남기지 않는 방식으로 전달해야 한다.

인터페이스:

```bash
./scripts/onboard-employee.sh \
  --username kim.chulsoo \
  --given-name Chulsoo \
  --surname Kim \
  --email kim.chulsoo@toss.lan \
  --department IT \
  --must-change-password true \
  --password-file /secure/path/temporary-password
```

`--password-file`을 생략하면 non-TTY stdin의 첫 줄 또는 대화형 `read -s`로
비밀번호를 받는다. 비밀번호 자체는 옵션 인자로 받지 않으며 로그와 리포트에
절대 쓰지 않는다. wrapper가 만든 mode `0600` extra-vars 파일에서 Ansible이
비밀번호를 읽고, 원격 Samba Python helper에는 process argument가 아닌 task
environment로 전달한다. helper는 `SamDB.newuser/setpassword`를 사용하며
environment에서 읽은 값을 즉시 제거한다. `must_change_password=true`는 account
expiry가 아니라 Samba의 password-change flag로 적용된다. password reset이
disabled bit를 바꾸더라도 후속 UAC 확인이 요청한 `ad_user_enabled` 상태로 다시
수렴시킨다.

## Verification Checklist

온보딩 실행 후 v1 검증 기준:

| Area | Check |
|---|---|
| AD | `samba-tool user show <username>` 성공 |
| AD | `mail:` attribute가 요청 email과 일치 |
| AD | 요청 부서 group에 user가 포함 |
| Password policy | AD minimum password length를 만족 |
| Password handling | CLI/process argument와 report에 비밀번호가 없음 |
| Password change | 요청 시 `--must-change-at-next-login` 적용 |
| Keycloak | homelab realm discovery endpoint HTTP 200 |
| Keycloak | LDAP federation baseline 검증 통과 |
| Nextcloud | OIDC provider, expected groups, external storage restriction 검증 통과 |
| Mail | Postfix/Dovecot service active 및 25/587/993 reachable |
| Wazuh | AD/Keycloak/Nextcloud/Mail 로그 수집 baseline 유지 |

wrapper가 내부에서 실행하는 주요 검증 명령:

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/employee-onboarding-verify.yml \
  -e @/secure/path/onboarding-vars.json \
  --vault-password-file .vault_pass
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags ad,keycloak,nextcloud,mail,wazuh --vault-password-file .vault_pass
```
전용 검증 playbook에는 `ad_user_name`, `ad_user_email`, 단일 항목의 `ad_user_groups`가 필요하다. wrapper는 AD 적용에 사용한 임시 extra-vars 파일을 재사용하며 실행 종료 시 삭제한다.

## Report Artifact

wrapper는 실행마다 아래 형식의 리포트를 생성한다.

```text
artifacts/onboarding/<UTC_TIMESTAMP>-<username>.md
```

리포트에 포함할 항목:

- Request summary: username, email, department, requested groups
- Execution summary: playbook, start/end time, return code
- Verification summary: AD, Keycloak, Nextcloud, Mail, Wazuh baseline
- Notification summary: Slack/Jira/GitHub skipped or sent
- Follow-up actions: initial password delivery, user guide, manual login test

`artifacts/`는 운영 증적이므로 secret 출력 여부를 확인한 뒤 보관한다.

## SQLite Record

MCP 기반 운영 DB에는 최소 다음 내용을 남긴다.

| Field | Value |
|---|---|
| `operation_type` | `employee_onboarding` |
| `target` | username |
| `status` | `success`, `failed`, `partial` |
| `summary` | one-line result |
| `details_json` | department, groups, email, report path, verify result |

현재 wrapper는 `.codex/mcp/homelab_ops.sqlite`의 `operations` table에 `employee_onboarding` 결과를 직접 기록한다. MCP helper는 이후 조회와 운영 자동화에서 같은 DB를 사용한다.

## Notification

`SLACK_WEBHOOK_URL`이 있으면 완료/실패 메시지를 보낸다.

권장 메시지:

```text
[homelab] employee onboarding success: kim.chulsoo / IT / report=<path>
```

webhook이 없으면 실패로 처리하지 않고 report에 `notification skipped`를 기록한다.

## Failure Handling

1. AD 생성 전에 실패한 경우: 입력값, password policy, active DC 상태를 확인한다.
2. AD 생성 후 group 부여가 실패한 경우: group 존재 여부를 확인하고 같은 wrapper 또는 `ad-onboard-user.yml`을 재실행한다.
3. Keycloak/Nextcloud 검증 실패: 먼저 `employee-onboarding-verify.yml`로 대상 사용자 검증을 재현하고, 필요하면 `identity-flow-verify.yml`로 전체 identity baseline을 확인한다.
4. Mail 검증 실패: `verify-all.yml --tags mail`과 `docs/services/nextcloud-mail.md`를 확인한다.
5. Slack 알림 실패는 AD 적용 성공을 rollback하지 않는다. report와 SQLite에는 `partial`로 기록한다.
6. 부분 성공 상태는 report와 SQLite에 `partial`로 남긴다.

복구 원칙: v1에서는 자동 삭제/rollback을 하지 않는다. 잘못 생성된 계정의
disable과 권한 회수는 별도
[Employee Offboarding Runbook](employee-offboarding-runbook.md)에서 다루며
계정 삭제는 자동화하지 않는다.

## Definition of Done

온보딩 v1 완료 기준:

- AD user exists
- expected AD group membership is present
- mail attribute is set
- identity/mail verification passed or failure is documented
- Markdown report exists
- SQLite operation record exists
- Slack notification sent or skipped with reason
- runbook remains in sync with implementation
