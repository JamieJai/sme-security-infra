# [Project 09] Endpoint 표준 앱 배포 자동화 및 관리자 권한 분리

*"도메인 가입 PC에서 일반 사용자에게 관리자 비밀번호를 공유하지 않고, 승인된 표준 앱을 SYSTEM 권한으로 배포하는 Endpoint 운영 자동화 검증"*

## 1. 개요 (Overview)

이번 작업은 Windows PC에 Nextcloud Desktop Client와 Nextcloud Talk Desktop을 설치하는 단순 앱 설치 문제가 아니라, 기업 IT 환경에서 자주 발생하는 "일반 사용자가 업무용 앱을 설치해야 하지만 관리자 권한은 줄 수 없는 문제"를 운영 자동화로 해결하는 과정이었다.

기존 Endpoint Onboarding 자동화가 PC를 AD 도메인에 안전하게 가입시키는 흐름이었다면, 이번 단계는 도메인 가입 이후의 표준 앱 배포까지 운영 workflow로 확장한 것이다.

핵심 목표는 다음과 같다.

- 사용자가 AD 관리자 비밀번호를 알지 못해도 표준 앱을 설치할 수 있게 한다.
- MSI 설치 권한은 사용자 토큰이 아니라 컴퓨터의 SYSTEM/elevated context로 처리한다.
- 앱 설치 파일은 SMB share에 두되, 사용자용 공용 share와 컴퓨터 계정용 배포 share를 분리한다.
- 배포 대상은 전체 도메인이 아니라 pilot security group으로 제한한다.
- 설치 결과는 detection rule, transcript log, scheduled task result, operations DB 기록으로 검증 가능하게 만든다.

## 2. 문제 발견 (Problem Identification)

### [현상]

도메인에 가입된 Windows PC에서 일반 사용자가 Nextcloud 관련 MSI를 실행하면 관리자 인증을 요구했다. 사용자는 업무 앱을 설치해야 하지만, 매번 관리자 비밀번호를 입력해야 하는 구조는 운영상 적절하지 않았다.

처음에는 `Z:` 드라이브 또는 `\\storage01\shared\endpoint-apps` 같은 사용자용 SMB 경로에 MSI를 두고 접근시키는 방향으로 보였지만, 이 방식에는 두 가지 한계가 있었다.

- MSI 파일을 읽을 수 있어도 설치 elevation은 별개의 문제다.
- SYSTEM 또는 GPO computer startup task는 사용자 계정이 아니라 컴퓨터 계정으로 SMB에 접근한다.

즉, 사용자가 파일을 볼 수 있는 것과 컴퓨터가 SYSTEM 권한으로 설치할 수 있는 것은 다른 문제였다.

### [임팩트]

- 사용자에게 관리자 비밀번호를 알려주면 권한 경계가 무너진다.
- IT 담당자가 매번 원격으로 로그인해 수동 설치하면 반복 업무가 늘어난다.
- 사용자가 직접 설치하는 방식은 PC마다 설치 상태가 달라져 표준화가 어렵다.
- 설치 파일을 공용 share에만 두면 GPO/SYSTEM 배포와 사용자 접근 권한이 섞인다.
- 전체 PC에 검증 없이 배포하면 실패 범위와 rollback 범위를 통제하기 어렵다.

이번 문제의 핵심은 "앱 설치 허용"이 아니라 "권한을 주지 않고도 표준 앱을 배포하는 운영 경로"를 만드는 것이었다.

## 3. 해결 과정 (Implementation)

### [기술적 조치 1: 표준 앱 catalog와 bootstrap script 구성]

먼저 표준 앱을 코드로 관리하기 위해 작은 catalog 기반 bootstrap 구조를 만들었다.

- `endpoint/windows/app-bootstrap/endpoint-app-catalog.json`
- `endpoint/windows/app-bootstrap/Install-EndpointApps.ps1`

Catalog에는 앱 이름, 설치 방식, MSI 경로, silent install argument, detection rule을 정의했다.

현재 enabled 앱은 다음 두 개다.

- Nextcloud Desktop Client
- Nextcloud Talk Desktop

설치는 `msiexec.exe /i <MSI> /qn /norestart ALLUSERS=1` 방식으로 실행하고, 설치 후에는 실제 실행 파일 경로가 존재하는지 확인한다.

Detection 기준:

```text
C:\Program Files\Nextcloud\nextcloud.exe
C:\Program Files\Nextcloud Talk\Nextcloud Talk.exe
```

이 구조를 통해 "설치 명령을 실행했다"에서 끝내지 않고, 실제 앱이 설치되었는지까지 검증할 수 있게 했다.

### [기술적 조치 2: 사용자용 share와 컴퓨터 배포용 share 분리]

처음 검증에서 SYSTEM scheduled task는 `\\storage01\shared\endpoint-apps`를 읽지 못했다. 원인은 파일 권한이 아니라 Samba share 설계였다.

`[shared]` share는 사용자용 공용 드라이브이며 `Domain Users` 중심으로 열려 있었다. 반면 SYSTEM/GPO task는 컴퓨터 계정으로 접근하기 때문에 `Domain Computers` 권한이 필요했다.

따라서 설치 파일 배포용 dedicated share를 분리했다.

```text
\\storage01\endpoint-apps
  -> /data/shared/endpoint-apps
```

`ansible/playbooks/storage-endpoint-app-installers.yml`로 다음을 보장했다.

- `/data/shared/endpoint-apps` directory 생성
- `IT_Admins` 관리 권한 부여
- `Domain Users`, `Domain Computers` read/traverse 권한 부여
- Samba `[endpoint-apps]` read-only share 게시
- bootstrap script와 catalog를 SMB 폴더에 배포
- 기존 MSI 파일 권한과 ACL 정렬

이후 catalog의 MSI 경로도 사용자용 share가 아니라 dedicated share 기준으로 수정했다.

```text
\\storage01\endpoint-apps\Nextcloud-33.0.7-x64.msi
\\storage01\endpoint-apps\Nextcloud.Talk-windows-x64.msi
```

중요한 설계 판단은 기존 `Z:` 공용 share 전체에 `Domain Computers`를 열지 않았다는 점이다. 컴퓨터 계정에 필요한 접근은 앱 배포용 share에만 제한했다.

### [기술적 조치 3: SYSTEM scheduled task로 실제 설치 검증]

`ODJ-VERIFY01` 테스트 VM에서 SYSTEM context 접근과 설치를 검증했다.

검증 흐름:

1. `ODJ-VERIFY01`에 local admin SSH로 접속
2. SYSTEM scheduled task 생성
3. task 내부에서 `\\storage01\endpoint-apps` 접근 확인
4. `Install-EndpointApps.ps1` 실행
5. 설치 결과와 detection path 확인
6. 임시 driver/runner script 삭제
7. 설치 결과 파일과 transcript log는 증적으로 보존

검증 결과:

- 실행 identity: `nt authority\system`
- `\\storage01\shared\endpoint-apps`: 실패, 정상 동작
- `\\storage01\endpoint-apps`: 성공
- `Install-EndpointApps.ps1`, catalog, 두 MSI list/read 성공
- Nextcloud Desktop Client 설치 성공
- Nextcloud Talk Desktop 설치 성공
- detection 통과

설치 로그:

```text
C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260711-204455.log
```

운영 DB에도 `endpoint_app_system_install` scope로 성공 기록을 남겼다.

### [기술적 조치 4: Pilot 배포 scope를 AD security group으로 제한]

전체 도메인 PC에 바로 GPO를 연결하지 않고, 첫 배포 scope를 `Endpoint_App_Install_Pilot` AD security group으로 제한했다.

추가한 자동화:

- `ansible/playbooks/endpoint-app-deployment-scope.yml`
- AD group: `Endpoint_App_Install_Pilot`
- pilot member: `ODJ-VERIFY01$`

적용 결과:

```text
Group DN: CN=Endpoint_App_Install_Pilot,CN=Users,DC=toss,DC=lan
Member DN: CN=ODJ-VERIFY01,CN=Computers,DC=toss,DC=lan
```

이 작업은 전체 PC 배포가 아니라, 이후 GPO security filtering 또는 endpoint management policy에서 사용할 pilot scope를 만든 것이다.

재실행 검증 중 Samba가 이미 존재하는 membership에 대해 `Attribute member already exists`를 반환해 playbook idempotency 조건도 보정했다. 최종 재실행은 `changed=0`으로 수렴했다.

### [기술적 조치 5: Pilot endpoint에 SYSTEM startup task 배포]

GPO security filtering을 바로 수작업으로 구성하기 전, pilot endpoint 한 대에 직접 SYSTEM startup scheduled task를 배포해 bootstrap 실행 경로를 검증했다.

추가한 자동화:

- `ansible/playbooks/endpoint-app-bootstrap-task.yml`
- `endpoint/windows/app-bootstrap/Configure-EndpointAppTask.ps1`
- inventory group: `windows_endpoint_pilot`
- target: `ODJ-VERIFY01`

등록된 task:

```text
Task name: Toss_EndpointAppBootstrap
Trigger: ONSTART
Run as: SYSTEM
Command: powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\storage01\endpoint-apps\Install-EndpointApps.ps1
```

초기 구현에서는 PowerShell `Register-ScheduledTask`가 `0x80070057` 오류를 반복했다. 그래서 Windows 기본 도구인 `schtasks.exe` 기반으로 바꾸고, local/remote SHA256 비교를 추가해 configurator script 복사도 idempotent하게 만들었다.

즉시 실행 검증 결과:

```text
lastTaskResult=0
NextcloudDesktop=True
NextcloudTalk=True
latest log=C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260712-134154.log
```

재실행 검증 결과:

```text
ok=5 changed=0 failed=0 skipped=1
```

### [기술적 조치 6: 재부팅 후 ONSTART trigger 검증]

마지막으로 `ODJ-VERIFY01`를 실제로 재부팅해 startup trigger가 부팅 시점에도 정상 실행되는지 확인했다.

검증 명령:

```bash
ansible all -i 'odj-verify01,' \
  -e ansible_host=192.168.0.77 \
  -e ansible_user=localadmin \
  -e ansible_connection=ssh \
  -m raw \
  -a "powershell.exe -NoLogo -NoProfile -NonInteractive -Command \"Restart-Computer -Force\""

ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-bootstrap-task.yml \
  -e endpoint_app_run_now=false
```

재부팅 후 검증 결과:

```text
lastTaskResult=0
NextcloudDesktop=True
NextcloudTalk=True
latest log=C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260712-141902.log
playbook recap: ok=5 changed=0 failed=0 skipped=1
operations DB: id=30, scope=endpoint_app_bootstrap_onstart_reboot_verify, status=success
```

이 결과로 단순 즉시 실행뿐 아니라 실제 부팅 트리거에서도 표준 앱 bootstrap이 정상 동작한다는 것을 확인했다.

## 4. 트러블슈팅 (Trouble Shooting)

### [문제 1: 사용자는 파일을 볼 수 있는데 설치는 관리자 인증을 요구함]

- **원인:** MSI 설치는 파일 접근 권한이 아니라 Windows elevation 권한 문제다.
- **해결:** 사용자가 직접 MSI를 실행하는 방식이 아니라, SYSTEM/elevated context에서 bootstrap을 실행하도록 설계를 바꿨다.
- **배움:** SMB read 권한과 Windows install 권한은 분리해서 봐야 한다.

### [문제 2: SYSTEM task가 SMB share를 읽지 못함]

- **원인:** SYSTEM task는 컴퓨터 계정으로 네트워크에 접근한다. 기존 `\\storage01\shared` share는 사용자용으로 설계되어 `Domain Computers`가 허용되지 않았다.
- **해결:** `\\storage01\endpoint-apps` dedicated share를 만들고 `Domain Computers` read/traverse 권한을 부여했다.
- **배움:** GPO computer startup, scheduled task, SYSTEM 배포는 사용자 세션과 다른 인증 경로를 사용한다.

### [문제 3: 전체 PC에 바로 배포할 수 있는가]

- **판단:** 기술적으로는 가능하지만, 전체 도메인 PC에 즉시 적용하지 않았다.
- **이유:** 앱 배포는 운영 변경이므로 OU 또는 보안 그룹으로 scope를 정한 뒤 pilot부터 배포해야 한다.
- **조치:** `Endpoint_App_Install_Pilot` group을 만들고 `ODJ-VERIFY01$`만 멤버로 추가했다.

### [문제 4: Scheduled task 자동화가 idempotent하지 않음]

- **원인:** Samba group membership은 이미 존재할 때 환경에 따라 다른 오류 문구를 반환했고, Windows scheduled task XML도 PowerShell CIM cmdlet이 기대한 형태와 달랐다.
- **해결:** Samba의 `Attribute member already exists`를 정상 수렴 조건에 포함했고, Windows task는 `schtasks.exe` XML 기준으로 비교했다.
- **배움:** 운영 자동화는 "성공한 첫 실행"보다 "반복 실행 시 변경 없음"을 더 엄격하게 봐야 한다.

### [문제 5: PowerShell 원격 실행 quoting과 Scheduler cmdlet 오류]

- **원인:** Windows OpenSSH 기본 shell과 PowerShell quoting이 섞이면서 긴 `EncodedCommand`와 일부 인자가 깨졌고, `Register-ScheduledTask`는 0x80070057 오류를 반환했다.
- **해결:** configurator script를 endpoint에 파일로 복사한 뒤 짧은 `-File` 명령으로 실행했고, task 생성은 `schtasks.exe`로 처리했다.
- **배움:** endpoint automation에서는 복잡한 원격 inline script보다 파일 배포 + 짧은 실행 명령이 추적과 재실행에 유리하다.

## 5. 결과 및 배움 (Result & Lessons)

### [결과]

- 일반 사용자에게 관리자 비밀번호를 공유하지 않고 표준 앱을 설치할 수 있는 경로를 검증했다.
- 앱 설치 파일은 SMB에 중앙 배치하고, 설치 실행은 SYSTEM context에서 처리하는 구조를 만들었다.
- 사용자용 공용 share와 컴퓨터 배포용 share를 분리해 권한 범위를 최소화했다.
- Nextcloud Desktop Client와 Nextcloud Talk Desktop의 실제 설치와 detection을 확인했다.
- Pilot AD security group을 만들고 `ODJ-VERIFY01`만 대상으로 제한했다.
- SYSTEM startup scheduled task를 구성하고, 즉시 실행과 재부팅 후 ONSTART 실행을 모두 검증했다.
- 설치 결과를 transcript log와 operations DB에 남겨 운영 증적으로 활용할 수 있게 했다.

### [검증 요약]

```text
endpoint_app_system_install: success
endpoint_app_deployment_pilot_group: success
endpoint_app_bootstrap_scheduled_task: success
endpoint_app_bootstrap_onstart_reboot_verify: success
```

주요 증적:

```text
C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260711-204455.log
C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260712-134154.log
C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260712-141902.log
```

### [배움: 권한을 주는 것보다 실행 주체를 바꾸는 것이 안전하다]

이번 문제는 사용자를 local admin으로 만들거나 관리자 비밀번호를 공유하면 빠르게 해결할 수 있었다. 하지만 그렇게 하면 Endpoint 보안의 기준이 무너진다.

더 안전한 방식은 사용자의 권한을 올리는 것이 아니라, 승인된 작업만 컴퓨터의 SYSTEM context에서 실행되도록 배포 경로를 설계하는 것이다.

```text
사용자에게 권한을 주지 않는다.
승인된 작업만 높은 권한으로 실행되게 한다.
```

이 원칙은 실제 기업 IT 운영에서 endpoint management, software deployment, GPO 설계를 할 때 매우 중요한 기준이 된다.

### [배움: 자동화는 scope와 rollback이 있어야 운영이 된다]

설치 자동화가 성공했다고 해서 곧바로 모든 PC에 배포하는 것은 좋은 운영이 아니다. 테스트 VM에서 검증하고, 이후 OU 또는 보안 그룹으로 배포 범위를 정하고, detection과 rollback 기준을 둬야 한다.

이번 검증은 전체 배포 전 단계로서 다음 기준을 확인했다.

- 컴퓨터 계정이 installer share를 읽을 수 있는가
- SYSTEM context에서 silent MSI install이 되는가
- startup trigger가 실제 부팅 시 실행되는가
- 설치 후 detection rule이 통과하는가
- 로그와 operations DB 증적이 남는가
- 자동화가 재실행 시 불필요한 변경 없이 수렴하는가

## 6. 향후 계획 (Next Steps)

- `ODJ-VERIFY01` pilot 방식이 안정적이므로, 다음 단계는 GPO/Scheduled Tasks preference 또는 endpoint management 도구로 일반화한다.
- 일반화할 때도 `Endpoint_App_Install_Pilot` security group 기준으로 먼저 제한한다.
- 여러 PC로 확장하기 전 rollback 절차를 문서화한다.
  - task rollback: `schtasks.exe /Delete /TN Toss_EndpointAppBootstrap /F`
  - scope rollback: `samba-tool group removemembers Endpoint_App_Install_Pilot <COMPUTER>$`
- 설치 실패 시 `C:\ProgramData\Toss\EndpointApps\Logs`와 detection path를 기준으로 helpdesk 진단 절차를 만든다.
- 장기적으로 Wazuh 또는 endpoint inventory와 연결해 앱 설치 상태를 중앙에서 확인한다.
