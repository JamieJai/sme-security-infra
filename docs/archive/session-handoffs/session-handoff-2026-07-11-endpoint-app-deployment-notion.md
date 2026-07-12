# Session Handoff - 2026-07-11 Endpoint App Deployment Notion Write-up

이 문서는 Endpoint 표준 앱 배포 자동화 작업과 Notion 포트폴리오 정리 결과를 다음 Codex 세션에서 바로 이어받기 위한 handoff다.

## 기준 상태

- Repo: `/home/sysadmin/homelab-infra`
- Branch: `main`
- Notion parent page: `https://app.notion.com/p/34a6d92ab08e802ab7d0f94293b1d2a3`
- 새 Notion page: `https://app.notion.com/p/39a6d92ab08e8176ab3af909d5875d20`
- 새 Notion title: `[Project 09] Endpoint 표준 앱 배포 자동화 및 관리자 권한 분리`
- 로컬 원고: `docs/portfolio/endpoint-app-deployment-system-install.md`

## 사용자가 요청한 것

사용자는 방금 검증한 Endpoint app 설치 흐름을 기존 Notion 포트폴리오 양식에 맞춰 정리하고, handoff 문서로도 남기길 요청했다.

참고하라고 준 페이지:

```text
https://app.notion.com/p/34a6d92ab08e802ab7d0f94293b1d2a3
```

## 확인한 Notion 양식

Notion 검색으로 기존 프로젝트 글과 최상위 페이지를 확인했다.

확인한 대표 글:

- `[Project 07] 중소기업형 보안 인프라 구축`
- `[Project 08] Endpoint Onboarding 자동화 및 ODJ 기반 PC 배포 설계`
- `[Project 06] 회고 Phase 2-1: IAM 자산 통합 자동화 및 보안 인증 레이어 고도화`
- `[Project 05] 회고 Phase 1: 보안 솔루션 고도화`

따른 양식:

- 제목은 `[Project XX] ...` 형식
- 첫 줄은 italic subtitle
- 본문 섹션은 다음 흐름 사용
  - `1. 개요 (Overview)`
  - `2. 문제 발견 (Problem Identification)`
  - `3. 해결 과정 (Implementation)`
  - `4. 트러블슈팅 (Trouble Shooting)`
  - `5. 결과 및 배움 (Result & Lessons)`
  - `6. 향후 계획 (Next Steps)`
- 단순 기능 나열보다 문제, 원인, 기술적 조치, 운영 판단, 배운 점을 연결하는 방식으로 작성

## 작성한 Notion 글 요지

제목:

```text
[Project 09] Endpoint 표준 앱 배포 자동화 및 관리자 권한 분리
```

Subtitle:

```text
"도메인 가입 PC에서 일반 사용자에게 관리자 비밀번호를 공유하지 않고, 승인된 표준 앱을 SYSTEM 권한으로 배포하는 Endpoint 운영 자동화 검증"
```

핵심 메시지:

- 일반 사용자가 MSI를 직접 실행하면 관리자 인증을 요구하는 것이 정상이다.
- 해결책은 사용자에게 local admin 권한을 주는 것이 아니라, 승인된 설치 작업만 SYSTEM/elevated context에서 실행되게 만드는 것이다.
- 사용자용 공용 SMB share와 컴퓨터 계정용 app deployment share는 분리해야 한다.
- 전체 PC 배포는 아직 하지 않았고, `ODJ-VERIFY01` 테스트 VM 한 대에서만 end-to-end 검증했다.
- 전체 배포는 OU 또는 security group scope를 정한 뒤 GPO computer startup script 또는 scheduled task preference로 진행해야 한다.

## 실제 검증 상태

운영 검증 완료:

- `endpoint/windows/app-bootstrap/endpoint-app-catalog.json`의 MSI 경로를 dedicated share 기준으로 변경
  - `\\storage01\endpoint-apps\Nextcloud-33.0.7-x64.msi`
  - `\\storage01\endpoint-apps\Nextcloud.Talk-windows-x64.msi`
- `ansible/playbooks/storage-endpoint-app-installers.yml` 적용
  - `[endpoint-apps]` share 추가
  - `Domain Users`, `Domain Computers`, `IT_Admins` 허용
  - `smbd` restart
- `ODJ-VERIFY01`에서 SYSTEM scheduled task로 `\\storage01\endpoint-apps` list/read 성공
- `ODJ-VERIFY01`에서 SYSTEM scheduled task로 실제 설치 성공
  - Nextcloud Desktop Client detection: `C:\Program Files\Nextcloud\nextcloud.exe=True`
  - Nextcloud Talk Desktop detection: `C:\Program Files\Nextcloud Talk\Nextcloud Talk.exe=True`
- 설치 log:
  - `C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260711-204455.log`
- operations DB record:
  - id `25`, scope `endpoint_app_system_install`, status `success`

주의:

- `\\storage01\shared\endpoint-apps`는 SYSTEM task에서 실패하는 것이 정상이다.
- `[shared]`는 사용자용 public share라 `Domain Computers`를 열지 않는다.
- GPO/SYSTEM 배포는 반드시 `\\storage01\endpoint-apps` dedicated share를 사용한다.

## Notion publish 결과

`mcp__homelab.notion_publish_project_file`는 실패했다.

원인:

```text
missing environment variables: NOTION_TOKEN
```

대신 Notion MCP `notion_create_pages`로 사용자가 준 parent page 아래에 직접 생성했다.

생성 결과:

```text
id: 39a6d92a-b08e-8176-ab3a-f909d5875d20
url: https://app.notion.com/p/39a6d92ab08e8176ab3af909d5875d20
title: [Project 09] Endpoint 표준 앱 배포 자동화 및 관리자 권한 분리
```

## 로컬 검증

게시 전 확인:

```bash
sed -n '1,260p' docs/portfolio/endpoint-app-deployment-system-install.md
scripts/check-no-secrets.sh
git diff --check
```

결과:

- 원고 내용 확인 완료
- `scripts/check-no-secrets.sh` 통과
- `git diff --check` 통과

## 다음에 바로 할 일

1. Notion UI에서 새 page가 최상위 포트폴리오 페이지의 원하는 위치에 보이는지 확인한다.
2. 필요하면 최상위 페이지의 프로젝트 목록에서 Project 09 링크 위치를 수동 조정한다.
3. 운영 구현의 다음 단계는 전체 배포가 아니라 배포 scope 설계다.
   - Endpoint OU를 만들지
   - software deployment용 AD security group을 만들지
   - `ODJ-VERIFY01`만 대상으로 GPO를 먼저 걸지 결정한다.
4. 결정 후 GPO computer startup script 또는 Scheduled Tasks preference로 다음 명령을 SYSTEM context에서 실행하게 한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\storage01\endpoint-apps\Install-EndpointApps.ps1
```

5. 각 endpoint에서 다음을 확인한다.

```powershell
Test-Path 'C:\Program Files\Nextcloud\nextcloud.exe'
Test-Path 'C:\Program Files\Nextcloud Talk\Nextcloud Talk.exe'
Get-ChildItem 'C:\ProgramData\Toss\EndpointApps\Logs'
```

## 변경 파일

이번 Notion 정리에서 새로 만든 파일:

- `docs/portfolio/endpoint-app-deployment-system-install.md`
- `docs/archive/session-handoffs/session-handoff-2026-07-11-endpoint-app-deployment-notion.md`

이미 이전 작업에서 변경된 관련 파일:

- `endpoint/windows/app-bootstrap/endpoint-app-catalog.json`
- `docs/services/endpoint-management.md`
- `docs/archive/session-handoffs/session-handoff-2026-07-06-it-operations-mcp.md`

## 2026-07-12 Endpoint App Deployment Scope Follow-up

이전 handoff의 "전체 배포 전 scope 설계"를 이어서 진행했다. 전체 도메인 PC 배포나 GPO 적용은 하지 않았다.

결정:

- 첫 배포 scope는 OU 이동이 아니라 AD security group `Endpoint_App_Install_Pilot`로 제한한다.
- pilot 대상 computer account만 명시적으로 그룹에 추가한다.
- GPO 또는 Scheduled Tasks preference는 이후 이 그룹으로 security filtering을 걸고 SYSTEM context에서 bootstrap을 실행하게 한다.

추가한 파일/문서:

- `ansible/playbooks/endpoint-app-deployment-scope.yml`
  - `Endpoint_App_Install_Pilot` 그룹을 생성한다.
  - `endpoint_app_deployment_computers`로 받은 computer account 존재 여부를 확인한다.
  - `<COMPUTER>$` 계정을 pilot 그룹에 추가한다.
- `docs/services/endpoint-management.md`
  - pilot scope 준비 절차, rollback, 적용 후 확인 명령을 추가했다.
- `docs/reference/ansible-playbook-catalog.md`
  - 새 playbook을 운영 작업 catalog에 추가했다.

검증:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/endpoint-app-deployment-scope.yml --syntax-check
scripts/check-no-secrets.sh
git diff --check
```

결과:

- 세 명령 모두 통과했다.
- operations DB record: id `26`, scope `endpoint_app_deployment_scope`, status `success`

다음에 바로 할 일:

1. 실제 pilot 대상이 `ODJ-VERIFY01` 하나인지 확인한다.
2. 승인 후 아래처럼 pilot group membership을 적용한다.

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-deployment-scope.yml \
  -e '{"endpoint_app_deployment_computers":["ODJ-VERIFY01"]}'
```

3. GPO/Scheduled Tasks preference는 `Endpoint_App_Install_Pilot`로 security filtering한다.
4. 실제 GPO 적용 전 rollback은 아래 명령으로 준비한다.

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool group removemembers Endpoint_App_Install_Pilot ODJ-VERIFY01$"
```

## 2026-07-12 Endpoint App Deployment Pilot Group Applied

사용자가 다음 단계 진행을 승인했고, pilot scope를 실제 AD에 적용했다.

적용 결과:

- `Endpoint_App_Install_Pilot` AD group 생성 완료
- `ODJ-VERIFY01$` computer account를 group member로 추가 완료
- group DN: `CN=Endpoint_App_Install_Pilot,CN=Users,DC=toss,DC=lan`
- member DN: `CN=ODJ-VERIFY01,CN=Computers,DC=toss,DC=lan`
- operations DB record: id `28`, scope `endpoint_app_deployment_pilot_group`, status `success`

실행 명령:

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-deployment-scope.yml \
  -e '{"endpoint_app_deployment_computers":["ODJ-VERIFY01"]}'
```

검증/수정:

- 첫 적용은 `changed=2`로 group 생성과 member 추가가 수행됐다.
- 재실행 검증 중 Samba가 이미 존재하는 membership에 대해 `Attribute member already exists`를 반환해 playbook idempotency 조건을 보정했다.
- 수정 후 재실행 결과: `ok=7 changed=0 failed=0 skipped=1`
- `ansible-playbook --syntax-check`, `scripts/check-no-secrets.sh`, `git diff --check` 통과

rollback:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool group removemembers Endpoint_App_Install_Pilot ODJ-VERIFY01$"
```

다음 단계:

1. GPO 또는 Scheduled Tasks preference를 `Endpoint_App_Install_Pilot` security filtering으로 제한한다.
2. task는 computer/SYSTEM context에서 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\storage01\endpoint-apps\Install-EndpointApps.ps1`만 실행한다.
3. 적용 후 `ODJ-VERIFY01`에서 `gpupdate /force`, app detection path, `C:\ProgramData\Toss\EndpointApps\Logs`를 확인한다.

## 2026-07-12 Endpoint App Bootstrap Scheduled Task Applied

Pilot group 적용 이후 GPO ACL 수작업 대신 `ODJ-VERIFY01`에 직접 SYSTEM startup scheduled task를 배포해 bootstrap 실행 경로를 검증했다.

추가/수정:

- `ansible/inventory/hosts`
  - `windows_endpoint_pilot` group 추가
  - `odj-verify01 ansible_host=192.168.0.77 ansible_user=localadmin ...` 등록
- `ansible/playbooks/endpoint-app-bootstrap-task.yml`
  - endpoint에 configurator script를 복사한다.
  - `Toss_EndpointAppBootstrap` task를 SYSTEM/ONSTART로 생성한다.
  - `endpoint_app_run_now=true`이면 즉시 실행하고 detection/log를 확인한다.
  - remote/local SHA256 비교로 configurator copy를 idempotent하게 만들었다.
- `endpoint/windows/app-bootstrap/Configure-EndpointAppTask.ps1`
  - `schtasks.exe` 기반으로 task를 생성한다.
  - PowerShell ScheduledTasks CIM cmdlet은 `Register-ScheduledTask` 0x80070057 오류가 반복되어 사용하지 않는다.

실행 결과:

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-bootstrap-task.yml \
  -e endpoint_app_run_now=true
```

- 대상: `ODJ-VERIFY01`
- task: `Toss_EndpointAppBootstrap`
- command: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\storage01\endpoint-apps\Install-EndpointApps.ps1`
- `lastTaskResult=0`
- detection: `NextcloudDesktop=True`, `NextcloudTalk=True`
- latest log: `C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260712-134154.log`

Idempotency:

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-bootstrap-task.yml \
  -e endpoint_app_run_now=false
```

최종 결과: `ok=5 changed=0 failed=0 skipped=1`

rollback:

```powershell
schtasks.exe /Delete /TN Toss_EndpointAppBootstrap /F
Remove-Item -LiteralPath C:\ProgramData\Toss\EndpointApps\Configure-EndpointAppTask.ps1 -Force
```

다음 단계:

1. `ODJ-VERIFY01`를 재부팅해 ONSTART trigger가 다시 정상 실행되는지 확인한다.
2. 재부팅 후 `lastTaskResult=0`, detection path, 최신 log timestamp를 확인한다.
3. 이 pilot 방식이 안정적이면 GPO/Scheduled Tasks preference 또는 endpoint management 도구로 배포 방식을 일반화한다.

## 2026-07-12 Project 09 Reboot Verification and Notion Replace Handoff

사용자가 `ODJ-VERIFY01` 재부팅 후 ONSTART scheduled task 검증까지 완료하고, Project 09 Notion page를 append가 아니라 전체 내용 교체 방식으로 수정해 달라고 요청했다.

완료한 검증:

- `ODJ-VERIFY01` 재부팅 실행 완료
- 재부팅 후 `ansible/playbooks/endpoint-app-bootstrap-task.yml -e endpoint_app_run_now=false` 실행
- 결과:
  - `lastTaskResult=0`
  - `NextcloudDesktop=True`
  - `NextcloudTalk=True`
  - latest log: `C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260712-141902.log`
  - play recap: `ok=5 changed=0 failed=0 skipped=1`
- operations DB record: id `30`, scope `endpoint_app_bootstrap_onstart_reboot_verify`, status `success`

로컬 원고 업데이트:

- `docs/portfolio/endpoint-app-deployment-system-install.md`를 전체 개정했다.
- 새 원고에는 다음 내용까지 포함된다.
  - dedicated endpoint app share
  - SYSTEM install 검증
  - `Endpoint_App_Install_Pilot` AD security group
  - `Toss_EndpointAppBootstrap` SYSTEM startup task
  - 재부팅 후 ONSTART 검증 결과
  - operations DB 증적과 rollback

검증:

```bash
scripts/check-no-secrets.sh
git diff --check
```

둘 다 통과했다.

Notion 상태:

- 대상 page: `https://app.notion.com/p/Project-09-Endpoint-39a6d92ab08e8176ab3af909d5875d20?source=copy_link`
- page id: `39a6d92a-b08e-8176-ab3a-f909d5875d20`
- 사용자가 명확히 요구한 방식: 아래에 append하지 말고 기존 page content를 전체 교체한다.
- 시도한 MCP: `mcp__notion.notion_fetch`
- 실패 원인:

```text
OAuth authorization required
```

다음 세션/사용자 조치:

1. Notion connector OAuth를 재인증한다.
2. `mcp__notion.notion_fetch`로 page를 먼저 읽어 child page/database 존재 여부를 확인한다.
3. child content가 없으면 `mcp__notion.notion_update_page`의 `replace_content`로 전체 본문을 교체한다.
4. Notion content는 `docs/portfolio/endpoint-app-deployment-system-install.md`에서 첫 번째 H1 title을 제외한 본문을 사용하고, page title은 `[Project 09] Endpoint 표준 앱 배포 자동화 및 관리자 권한 분리`로 유지한다.
5. replace 후 fetch로 반영 여부를 확인한다.

