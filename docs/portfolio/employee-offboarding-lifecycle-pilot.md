# Employee Offboarding Lifecycle Pilot

검증일: `2026-07-29`

이 문서는 개인 homelab의 전용 test identity로 onboarding, offboarding,
verification, recovery, idempotency, final containment를 수행한 기록이다. 실제
임직원이나 production 계정을 처리한 경험으로 표현하지 않는다.

## 목표

계정 삭제 없이 다음 lifecycle이 실제 상태와 운영 증적에서 일치하는지 확인했다.

1. test identity onboarding
2. 지급 자산 등록
3. 변경 없는 offboarding plan
4. AD disable과 managed group 회수
5. Keycloak session gate와 Nextcloud user 처리
6. verification 후 자산 `recovery_pending` 전환
7. 별도 승인 recovery
8. recovery 재실행의 `changed=0` 수렴
9. test identity final containment

## Pilot 대상

| 항목 | 값 |
|---|---|
| Identity | `offboard.pilot` |
| AD group | `HR_Staff` |
| Asset | `PC-OFFPILOT01` |
| Asset initial status | `assigned` |
| Environment | 개인 Proxmox homelab |
| Data | test identity와 모의 자산 record |

임시 비밀번호는 `/tmp`의 mode `0600` 파일로 전달하고 onboarding 종료 직후
삭제했다. 비밀번호, Vault 값, Keycloak admin credential은 report와 Git에
기록하지 않았다.

## 실행 결과

| 단계 | 결과 | 핵심 증거 |
|---|---|---|
| Onboarding | Success | AD user `512`, `HR_Staff`, 서비스 baseline 통과 |
| Offboarding plan | Planned | 자산은 `assigned` 유지, operation만 기록 |
| Execute attempt 1 | Partial | UAC parser가 실제 변경 전에 중단 |
| Execute attempt 2 | Partial | AD `514`와 group 회수 후 Keycloak users API 400 |
| Execute retry | Success | 기존 차단 상태에서 apply `changed=0`, verify 성공 |
| Recovery plan | Planned | `HR_Staff`와 previous asset status 확인 |
| Recovery execute | Success | AD enable, group 복구, asset `assigned` 복귀 |
| Recovery retry | Success | apply와 verify 모두 `changed=0` |
| Final containment | Success | AD `514`, managed group 없음, asset recovery pending |

SQLite operations ID 기준 실행 이력은 `7`, `9`-`18`에 기록됐다. generated
artifact와 SQLite DB는 운영 증적이므로 `.gitignore` 대상이며 저장소에는
비밀정보가 없는 이 요약만 커밋한다.

## 발견한 문제 1: UAC parser

첫 execute는 `samba-tool user show` 결과의 `userAccountControl`을 찾는 Jinja
regex가 빈 목록을 반환해 중단됐다.

**영향**

- AD disable과 group removal 전이므로 identity 상태는 변하지 않았다.
- 승인된 자산 회수 요청은 독립적으로 `recovery_pending`에 남았다.
- operation은 `partial`, apply return code `2`로 기록됐다.

**개선**

- Samba 조회를 `--attributes=userAccountControl --color=never`로 제한했다.
- 공백 escape 대신 `[0-9]` 기반 pattern으로 네 apply/verify playbook을 통일했다.
- fix commit: `8b5627e`

## 발견한 문제 2: Keycloak users API

두 번째 execute에서 AD disable과 `HR_Staff` 회수는 성공했지만 Keycloak 22.0.1의
LDAP federation 환경에서 Admin REST `users` 목록이 HTTP 400
`unknown_error`를 반환했다.

**영향**

- identity는 이미 차단됐으므로 자동 rollback하지 않았다.
- verification과 DB에는 `partial`로 남기고 자산은 `recovery_pending`을 유지했다.
- Keycloak `client-session-stats` 결과는 빈 목록으로 active realm session이
  없음을 별도로 확인했다.

**개선**

- realm client session이 0이면 user lookup과 logout을 생략한다.
- session이 있을 때만 exact username 조회와 user logout을 수행한다.
- user 조회가 실패하면 성공으로 숨기지 않고 계속 `partial`로 중단한다.
- fix commit: `8b134dd`

추가 preflight에서 account를 다시 enabled 상태로 복구한 뒤에도 `users` API는
같은 400을 반환했다. 따라서 active session을 의도적으로 만들지 않고 즉시 final
containment로 되돌렸다. 동시에 여러 `kcadm.sh` read를 실행했을 때 local config
lock 경합도 확인했으므로 Admin CLI 작업은 직렬 실행한다.

## Retry와 상태 보존

partial execute 후 자산이 이미 `recovery_pending`인 상태에서 재시도하면 현재
status를 원래 status로 덮어쓸 위험이 있었다. wrapper가 기존
`metadata_json.offboarding.previous_status`를 우선 사용하도록 수정하고 fixture에
retry case를 추가했다.

최종 자산 metadata는 다음 의미를 가진다.

| Field | Final meaning |
|---|---|
| `status` | `recovery_pending` |
| `owner` | `offboard.pilot`로 마지막 책임 관계 보존 |
| `offboarding.previous_status` | `assigned` |
| `offboarding.recovery_status` | final containment 기준 `pending` |
| `offboarding_recovery.restored_status` | 중간 recovery에서 `assigned` 복구 완료 |

## 검증된 범위

- 전용 AD user 생성, mail attribute와 `HR_Staff` 부여
- AD enabled `512`에서 disabled `514` 전환
- 네 managed group에서 exact username 부재 검증
- Keycloak realm active session 0 확인과 zero-session gate
- 자산 `assigned → recovery_pending → assigned → recovery_pending` lifecycle
- recovery에서 승인한 group만 복구
- recovery apply/verify 재실행 `changed=0`
- final containment 후 AD/Keycloak/Nextcloud/Mail/Wazuh baseline `changed=0`
- Markdown report와 SQLite operation 상태 일치
- account, mailbox, file, home directory, asset record 삭제 없음

## 검증하지 않은 범위

- 실제 active Keycloak session의 exact-user logout branch
- provision된 Nextcloud local user의 disable/enable branch
- 실제 임직원, 실제 지급 장비 또는 production tenant
- 데이터 보존 기간 종료 후 삭제와 remote wipe

현재 Keycloak realm에는 active session이 없었기 때문에 session revoke 코드는
구현 및 gate 검증 상태이며 live session revoke 성공으로 주장하지 않는다.
Nextcloud에도 해당 local user가 없어 AD source containment만 검증했다.

## 면접 설명 요약

> 삭제 대신 disable-first 오프보딩을 구현하고 전용 test identity로 차단과 복구를
> 실제 검증했습니다. 첫 실행에서 UAC parser, 다음 실행에서 Keycloak users API
> 오류를 만나 부분 성공을 숨기지 않고 기록했습니다. 이후 pre-change parsing,
> zero-session gate, retry 시 previous asset status 보존을 추가했고, 최종적으로
> AD 권한 회수와 복구 재실행의 changed=0 수렴까지 확인했습니다.

## 관련 구현

- [Offboarding wrapper](../../scripts/offboard-employee.sh)
- [Recovery wrapper](../../scripts/recover-offboarded-employee.sh)
- [Offboarding playbook](../../ansible/playbooks/employee-offboarding.yml)
- [Recovery playbook](../../ansible/playbooks/employee-offboarding-recovery.yml)
- [Operations runbook](../operations/employee-offboarding-runbook.md)
