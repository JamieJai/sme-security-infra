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
| LDAP HA recovery | Success | local alias 영속화, 재실행 `changed=0`, exact user 조회 복구 |
| Active session pilot | Success | `grafana` session 생성, exact-user logout, session 0 |
| Nextcloud OIDC pilot | Success | `user_oidc`, `HR_Staff`, local user provision |
| Nextcloud offboarding | Success | OIDC session logout과 local user disable |
| Nextcloud recovery | Success | local user enable, 재실행 `changed=0` |
| Final containment | Success | AD `514`, group 없음, Nextcloud disabled, session 0 |

SQLite operations ID 기준 실행 이력은 `7`, `9`-`32`에 기록됐다. generated
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

## 발견한 문제 2: Keycloak LDAP HA name-resolution drift

두 번째 execute에서 AD disable과 `HR_Staff` 회수는 성공했지만 Keycloak 22.0.1의
LDAP federation 환경에서 Admin REST `users` 목록이 HTTP 400
`unknown_error`를 반환했다. 후속 Keycloak stack trace에서 실제 원인은
`keycloak-ldap-ha.toss.lan:1636` connection refused로 확인됐다.

**영향**

- identity는 이미 차단됐으므로 자동 rollback하지 않았다.
- verification과 DB에는 `partial`로 남기고 자산은 `recovery_pending`을 유지했다.
- HAProxy는 `127.0.0.1:1636`에서 active였지만 cloud-init이 `/etc/hosts`의 local
  alias를 지워 이름이 `192.168.0.60`으로 해석됐다.

**개선**

- `/etc/hosts`와 `/etc/cloud/templates/hosts.debian.tmpl`에
  `keycloak-ldap-ha.toss.lan -> 127.0.0.1`을 함께 수렴시켰다.
- HAProxy config, 두 DC의 `636`, loopback TLS hostname verification을 확인했다.
- HA playbook 재실행은 `changed=0`, Admin REST exact user 조회는 1건으로 복구됐다.
- session revoke는 `/users` 목록 대신 active client session에서 exact username과
  user ID를 찾도록 구현했다.

동시에 여러 `kcadm.sh` read를 실행했을 때 local config lock 경합도 확인했으므로
Admin CLI 작업은 직렬 실행한다.

## 발견한 문제 3: federated user cache

AD recovery 직후 controlled direct-grant는 HTTP 400을 반환했고 Keycloak event는
`error=user_disabled`를 기록했다. AD는 enabled였지만 Keycloak user cache에 이전
disabled 상태가 남아 있었다.

Keycloak 22 Admin REST에는 개별 federated user cache eviction endpoint가 없어
offboarding과 recovery의 Admin CLI 인증 직후 realm `clear-user-cache`를 실행한다.
이 작업은 session을 복구하거나 삭제하지 않으며 다음 user read를 AD 원본에서 다시
수행하게 한다. 적용 후 exact user는 `enabled=True`로 확인됐고 controlled login이
성공했다.

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
- `grafana` direct-grant active session 생성과 exact-user logout
- Nextcloud OIDC login의 state, nonce, PKCE callback 완료
- `user_oidc` backend local user와 `HR_Staff` group provision
- active `nextcloud-oidc` session logout과 local user disable
- 승인 recovery의 Nextcloud user enable과 재실행 `changed=0`
- Keycloak LDAP HA alias 영속화와 playbook 재실행 `changed=0`
- 자산 `assigned → recovery_pending → assigned → recovery_pending` lifecycle
- recovery에서 승인한 group만 복구
- recovery apply/verify 재실행 `changed=0`
- final containment 후 AD/Keycloak/Nextcloud/Mail/Wazuh baseline `changed=0`
- Markdown report와 SQLite operation 상태 일치
- account, mailbox, file, home directory, asset record 삭제 없음

## 검증하지 않은 범위

- 실제 임직원, 실제 지급 장비 또는 production tenant
- 데이터 보존 기간 종료 후 삭제와 remote wipe
- Playwright screenshot 기반 UI 검증

Playwright MCP는 실행 환경에 Chrome distribution이 없어 시작되지 않았다. 대신
전용 test identity로 실제 Nextcloud OIDC authorization flow와 callback을 완료하고
서버의 `occ user:info`, Keycloak client session, offboarding verification으로
상태를 검증했다. 실제 임직원 또는 production 운영 경험으로 표현하지 않는다.

## 면접 설명 요약

> 삭제 대신 disable-first 오프보딩을 구현하고 전용 test identity로 차단과 복구를
> 실제 검증했습니다. UAC parser, LDAP HA name-resolution drift, federated user
> cache 문제를 부분 성공과 로그로 남긴 뒤 수정했습니다. 이후 Grafana와 Nextcloud
> OIDC active session의 exact-user logout, Nextcloud disable/enable, AD 권한 회수,
> 자산 상태 보존과 재실행 changed=0까지 확인했습니다.

## 관련 구현

- [Offboarding wrapper](../../scripts/offboard-employee.sh)
- [Recovery wrapper](../../scripts/recover-offboarded-employee.sh)
- [Offboarding playbook](../../ansible/playbooks/employee-offboarding.yml)
- [Recovery playbook](../../ansible/playbooks/employee-offboarding-recovery.yml)
- [Operations runbook](../operations/employee-offboarding-runbook.md)
