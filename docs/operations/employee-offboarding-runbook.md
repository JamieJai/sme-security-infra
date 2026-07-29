# Employee Offboarding Runbook

이 runbook은 퇴사 또는 장기 접근 중단 요청을 계정 삭제 없이 처리하는 표준
절차다. AD를 인증 원본으로 두고 접근을 먼저 차단한 뒤 세션, 부서 권한, 자산
회수 상태를 검증 가능한 증적으로 남긴다.

## 운영 원칙

- 기본 모드는 변경 없는 `plan`이다.
- 실제 적용에는 티켓, 승인자, 정확한 사용자명 재확인이 모두 필요하다.
- AD 계정, Mail, Nextcloud 파일, 홈 디렉터리와 자산 record를 삭제하지 않는다.
- 관리 대상 부서 그룹만 회수하며 그 외 그룹은 별도 검토 대상으로 남긴다.
- 자산은 owner를 지우지 않고 `recovery_pending`으로 전환해 마지막 책임 관계를
  보존한다.
- 잘못된 요청에 대비해 복구 순서를 실행 전에 확인한다.

## 범위

v1이 처리하는 항목:

| 영역 | 조치 |
|---|---|
| AD | 계정 disable |
| 권한 | `HR_Staff`, `Finance_Staff`, `IT_Admins`, `Security_Team` 회수 |
| Keycloak | exact username의 모든 active session revoke |
| Nextcloud | exact local user가 있을 때 disable |
| Mail | AD disable을 통한 신규 인증 차단 |
| 자산 | 해당 owner의 asset을 `recovery_pending`으로 전환 |
| 증적 | Markdown report와 SQLite operation record |

v1에서 제외하는 항목:

- 계정, mailbox, 파일 또는 home directory 삭제
- 자동 데이터 이관과 보존 기간 만료 처리
- AD computer object disable 또는 endpoint remote wipe
- license 회수, SaaS tenant 계정 처리
- 예약된 미래 시각의 자동 실행
- 승인 없는 실제 적용

## 변경 전 복구 계획

실행 전에 아래 복구 가능성을 확인한다.

1. AD 계정은 `samba-tool user enable <username>`으로 다시 활성화할 수 있다.
2. 회수할 부서 그룹과 원래 membership을 티켓에 남긴다.
3. Nextcloud local user가 있으면 `user:enable`로 복구할 수 있다.
4. 자산의 기존 status는
   `metadata_json.offboarding.previous_status`에 보존한다.
5. 복구도 원 요청과 분리된 승인 티켓 및 operation record로 남긴다.

계정 삭제와 데이터 삭제는 이 workflow의 rollback 범위를 벗어나므로 수행하지
않는다.

## Plan

다음 명령은 서비스 상태를 변경하지 않는다. 현재 operations DB에서 사용자에게
할당된 자산을 읽고 계획 report와 `employee_offboarding_plan` record만 만든다.

```bash
./scripts/offboard-employee.sh \
  --username kim.chulsoo \
  --ticket-ref OFF-2026-001 \
  --reason "Employment ended" \
  --effective-at "2026-07-31T09:00:00+09:00"
```

확인 항목:

- username과 티켓의 대상자가 일치하는가
- 요청 효력 시각이 맞는가
- 회수 예정 부서 그룹에 예외가 없는가
- report의 assigned asset 목록이 실제 지급 내역과 일치하는가
- 데이터 보존 및 업무 인수인계 담당자가 지정됐는가

`--effective-at`은 v1에서 증적용 요청 시각이며 예약 실행 기능이 아니다. 실제
적용 명령을 실행한 시점에 접근이 차단된다.

## Execute

실제 적용은 production-impacting operation이다. 승인된 요청을 확인한 소유자만
실행한다.

```bash
./scripts/offboard-employee.sh \
  --username kim.chulsoo \
  --ticket-ref OFF-2026-001 \
  --reason "Employment ended" \
  --effective-at "2026-07-31T09:00:00+09:00" \
  --approved-by it.manager \
  --execute \
  --confirm-username kim.chulsoo
```

wrapper와 playbook은 다음 gate를 중복 적용한다.

- `administrator`, `guest`, `krbtgt`, `sysadmin` 보호 계정 거부
- ticket과 approver 필수
- `--username`과 `--confirm-username` exact match
- playbook 내부의 `offboarding_authorized=true` 확인
- account deletion task 부재

## 실행 순서

1. AD 사용자가 존재하는지 확인한다.
2. 관리 대상 부서 그룹 membership을 조회한다.
3. 실제 포함된 관리 대상 그룹에서만 사용자를 제거한다.
4. AD userAccountControl을 확인하고 enabled 상태일 때만 disable한다.
5. Keycloak user cache를 비워 AD의 최신 disable 상태를 다시 읽게 한다.
6. active client session에서 exact username을 선택하고 모든 session을 revoke한다.
7. 동일한 Nextcloud local user가 존재하고 enabled이면 disable한다.
8. 별도 verification playbook으로 AD disable, group removal, Keycloak session 0,
   Nextcloud disable을 확인한다.
9. 승인된 execute 요청이면 identity 적용 결과와 별개로 할당 asset을
   `recovery_pending`으로 전환한다.
10. Markdown report와 `employee_offboarding` SQLite record를 작성한다.

## 완료 기준

| 검증 | 완료 조건 |
|---|---|
| AD | disabled bit가 설정됨 |
| 부서 권한 | 네 개 managed group에 username이 없음 |
| Keycloak | exact username의 active session이 0개 |
| Nextcloud | local user가 있으면 `enabled: false` |
| 자산 | 할당 asset이 `recovery_pending`, 이전 status가 metadata에 보존됨 |
| 증적 | report와 SQLite operation record가 존재 |
| 데이터 | 삭제 작업이 수행되지 않음 |

Keycloak에 exact user session이 없거나 Nextcloud local user가 생성되지 않은
경우는 실패가 아니다. 인증 원본인 AD disable과 관리 그룹 회수가 완료됐는지를
기준으로 판단하고 report에 해당 상태를 남긴다.

Nextcloud 조회에서 `user not found`는 정상적인 미프로비저닝 상태로 처리한다.
그 외 `occ user:info` 오류는 PHP, DB 또는 application 장애일 수 있으므로
offboarding/recovery를 성공으로 기록하지 않고 중단한다. user enabled 상태는
사람이 읽는 문자열이 아니라 `--output=json` 결과로 판정한다.

## 상태 분류

| 상태 | 의미 |
|---|---|
| `planned` | 서비스 변경 없이 계획과 자산 목록만 기록 |
| `success` | 접근 차단, 검증, 자산 상태와 DB 기록 완료 |
| `partial` | 접근 차단은 적용됐지만 verification 또는 DB 기록 실패 |
| `failed` | 실행 gate 이전 또는 운영 기록 단계에서 workflow 시작 실패 |

`partial` 상태에서는 AD 또는 연계 서비스 일부만 변경됐을 수 있으며 자산 회수는
계속 필요하다. 자동 rollback하지 말고 apply log와 verification log를 먼저
확인한다.

## Recovery

승인 오류 또는 복직으로 접근을 복구할 때도 plan과 execute를 분리한다. 먼저
복구 대상 group과 asset previous status를 확인한다.

```bash
./scripts/recover-offboarded-employee.sh \
  --username kim.chulsoo \
  --ticket-ref REC-2026-001 \
  --reason "Approved employment restoration" \
  --group IT_Admins
```

승인 후 실제 복구:

```bash
./scripts/recover-offboarded-employee.sh \
  --username kim.chulsoo \
  --ticket-ref REC-2026-001 \
  --reason "Approved employment restoration" \
  --group IT_Admins \
  --approved-by it.manager \
  --execute \
  --confirm-username kim.chulsoo
```

그룹은 기존 티켓과 offboarding report에 있던 항목만 복구한다. AD enable 뒤
Keycloak realm user cache를 비워 federation의 이전 disabled 상태가 남지 않게
한다. 이 작업은 기존 session을 복구하지 않으며 사용자가 새로 로그인하게 한다.
identity와 group verification이 통과한 경우에만 asset status를
`offboarding.previous_status`로 되돌린다.

## 검증 및 테스트

repository 수준 검증:

```bash
python3 -m unittest -q tests/test_offboard_employee.py
python3 -m unittest -q tests/test_recover_offboarded_employee.py
cd ansible
ansible-playbook -i inventory/hosts --syntax-check \
  playbooks/employee-offboarding.yml
ansible-playbook -i inventory/hosts --syntax-check \
  playbooks/employee-offboarding-verify.yml
ansible-playbook -i inventory/hosts --syntax-check \
  playbooks/employee-offboarding-recovery.yml
ansible-playbook -i inventory/hosts --syntax-check \
  playbooks/employee-offboarding-recovery-verify.yml
```

fixture test는 임시 SQLite DB를 사용해 plan mode가 자산 상태를 바꾸지 않는지,
execute gate와 보호 계정 차단, 성공 검증 전 asset recovery 차단이 동작하는지
확인한다. 실제 계정 차단과 복구 검증은 승인된 test identity로 별도 실행한다.

## Live Pilot

`2026-07-29`에 전용 test identity `offboard.pilot`과 모의 자산
`PC-OFFPILOT01`로 다음을 검증했다.

- onboarding 후 AD `512`, `HR_Staff`, 자산 `assigned`
- offboarding 후 AD `514`, managed group 없음, 자산 `recovery_pending`
- 별도 recovery 후 AD enable, 승인 group 복구, 자산 `assigned`
- recovery 재실행 apply/verify `changed=0`
- `grafana`와 `nextcloud-oidc` active session의 exact-user logout
- Nextcloud `user_oidc` local user의 disable, recovery enable, 재실행 `changed=0`
- final containment 후 AD `514`, group 없음, Nextcloud disabled, session 0,
  자산 `recovery_pending`

실제 임직원이 아닌 전용 test identity로만 수행했다. 중간 실패와 수정 내역은
[Employee Offboarding Lifecycle Pilot](../portfolio/employee-offboarding-lifecycle-pilot.md)에
정리했다.
