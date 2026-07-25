# Endpoint Management

이 문서는 IT Manager 포트폴리오 관점의 Windows/macOS 단말 운영 방향을 정리한다. 현재 우선순위는 Windows 신규 PC를 AD에 안전하게 join시키는 셀프서비스 흐름이다.

## Windows AD Join Self-Service

목표 흐름:

```text
신입사원 또는 IT 담당자
  -> 온보딩 포털 접속
  -> /endpoint/windows/ad-join?employee_id=<사번> 형태로 접근
  -> 사번 기반 join package 다운로드
  -> 로컬 관리자 권한으로 실행
  -> DNS 확인 또는 설정
  -> AD credential 입력
  -> Windows PC domain join 및 reboot
```

현재 v1 구현:

- `endpoint/windows/ad-join-self-service/Join-HomelabDomain.ps1`
  - Windows에서 실행하는 domain join PowerShell template.
  - script 자체에 도메인 join 비밀번호나 token을 포함하지 않는다.
  - 필요 시 DNS server를 설정하고 `Add-Computer`로 domain join을 수행한다.
- `scripts/generate-windows-ad-join-package.sh`
  - `employee_id` 기준으로 다운로드 가능한 package directory를 생성한다.
  - `run-as-admin.cmd`, PowerShell script, README를 생성한다.
  - 기본 DNS는 현재 AD DNS 기준인 `192.168.0.21,192.168.0.20`을 사용한다.

예시:

```bash
./scripts/generate-windows-ad-join-package.sh \
  --employee-id 20260706-001 \
  --computer-name PC-2026070601
```

생성 위치:

```text
artifacts/endpoint-join/<employee_id>/
```

이 directory를 사내 onboarding portal 또는 Nextcloud restricted share에 게시하면, 사용자는 자기 사번에 해당하는 package만 내려받아 실행할 수 있다.

## 보안 원칙

스크립트 다운로드 방식에서 가장 위험한 것은 domain join 권한 credential 유출이다. 따라서 v1에서는 아래를 금지한다.

- PowerShell script에 domain admin, join account password, API token 삽입 금지
- URL query parameter에 password/token 삽입 금지
- 공유 링크를 전체 공개로 배포 금지
- raw execution log에 credential 입력값 저장 금지

권장 방식:

1. v1: 스크립트는 credential을 포함하지 않고, 실행 시 `Get-Credential`로 AD credential을 입력받는다.
2. v2: Offline Domain Join(`djoin.exe`) blob을 서버에서 사전 생성하고, 사용자별/장비별 단일 package로 배포한다.
3. v3: 온보딩 포털에서 인증된 사용자만 package를 받을 수 있게 하고, 다운로드/실행 결과를 SQLite/Slack/Notion에 기록한다.

## DNS 처리

AD Join은 클라이언트가 AD DNS를 사용해야 안정적으로 동작한다. 사용자가 직접 DNS를 설정해야 하는 환경이면 onboarding guide에 아래를 명시한다.

- AD DNS 서버 IP
- DNS 변경 방법
- `Resolve-DnsName toss.lan` 확인 방법
- 실패 시 IT팀에 전달할 screenshot/log 항목

현재 PowerShell script는 `-DnsServers` 값이 전달되면 활성 NIC의 DNS server를 설정한다. 권한 문제 또는 네트워크 정책 때문에 실패할 수 있으므로, 수동 DNS 설정 절차도 유지한다.

## Windows Management VM for ODJ

ODJ v2를 구현하려면 `djoin.exe /provision`을 실행할 Windows 관리 호스트가 필요하다. Windows Server를 새로 도입하지 않고, 라이선스가 있는 Windows 11 Pro/Enterprise VM을 RSAT/djoin 전용 관리 호스트로 사용하는 방향을 기준으로 둔다.

현재 Terraform에는 optional Windows VM module이 추가되어 있다.

- Module: `terraform/modules/windows-vm`
- Variable: `windows_vms`
- Example: `terraform/terraform.tfvars.example`
- 기본값은 `{}`라서 기존 Ubuntu VM에는 영향이 없다.

필요한 사전 조건:

1. Proxmox `local` storage에 Windows 11 ISO 업로드
2. Proxmox `local` storage에 VirtIO driver ISO 업로드
3. local-only `terraform/terraform.tfvars`에 `windows_vms.win-mgmt01` 블록 추가
4. `terraform plan`에서 `win-mgmt01` 1개 생성만 표시되는지 확인
5. `terraform apply` 후 Proxmox console에서 Windows 설치
6. Windows 정품 인증은 보유한 합법 라이선스와 공식 활성화 방식만 사용
7. RSAT/AD DS tools와 필요한 경우 OpenSSH/WinRM을 활성화
8. 이후 `djoin.exe /provision` 기반 ODJ blob 생성 workflow를 구현

보안 기준:

- Windows management VM은 일반 업무/브라우징용이 아니라 RSAT/djoin 전용으로 사용한다.
- domain admin 대신 ODJ/join 전용 delegated account를 사용한다.
- ODJ blob은 민감 자료로 취급하고 사용자/장비별로 발급한다.
- blob 저장 위치는 접근 제한하고, 발급/다운로드/폐기 이력을 SQLite/Slack/Notion workflow와 연결한다.
- v1 `Join-HomelabDomain.ps1` 방식은 ODJ 준비 전 fallback으로 유지한다.

## Offline Domain Join v2 설계

더 안전하고 사용자 경험이 좋은 방식은 Windows의 Offline Domain Join이다.

개념:

```text
IT automation host
  -> djoin /provision 으로 장비별 blob 생성
  -> package에 blob + apply script 포함
  -> 사용자 PC에서 djoin /requestODJ 실행
  -> reboot 후 domain joined 상태로 전환
```

장점:

- 사용자에게 domain join service account password를 요구하지 않는다.
- package를 장비별로 만들 수 있다.
- 포털 다운로드 기록과 AD computer object를 매칭하기 쉽다.

주의:

- `djoin /provision`을 실행할 Windows 관리 호스트 또는 RSAT 환경이 필요하다.
- 생성된 blob은 민감한 가입 자료이므로 만료/회수/접근제어 정책이 필요하다.
- 잘못 배포된 blob은 해당 computer object를 disable/delete하는 recovery 절차와 연결해야 한다.

현재 v2 자동화:

- `ansible/inventory/hosts`
  - `windows_management` group에 `win-mgmt01`을 등록한다.
  - SSH transport와 PowerShell shell을 사용한다.
- `ansible/playbooks/windows-odj-provision.yml`
  - `win-mgmt01`에서 `djoin.exe` 존재 여부, domain join 상태, DC discovery를 확인한다.
  - vaulted `ad_admin_password`를 사용해 `Administrator@toss.lan` 권한의 1회성 scheduled task를 등록한다.
  - task 안에서 `djoin.exe /provision /domain toss.lan /machine <COMPUTER> /savefile <BLOB>`을 실행한다.
  - task와 임시 script를 삭제하고 blob ACL을 `SYSTEM`과 `Administrators`로 제한한다.
  - 기본값으로 scp를 사용해 blob을 `artifacts/endpoint-odj-blobs/<COMPUTER>.blob`에 가져온다.
- `endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1`
  - 사용자 PC에서 ODJ blob을 `djoin.exe /requestODJ /loadfile ... /localos`로 적용한다.
  - 로컬 관리자 권한, computer name 형식, blob 존재 여부를 확인한다.
  - DNS를 AD DNS로 설정하고 재부팅한다.
- `scripts/generate-windows-odj-package.sh`
  - 가져온 blob과 apply script를 `artifacts/endpoint-odj/<employee_id>/<computer_name>/`에 묶는다.
  - package 생성 이력을 `.codex/mcp/homelab_ops.sqlite`의 `operations` table에 `endpoint_odj_package`로 기록한다.

발급 예시:

```bash
cd ansible
ansible-playbook -i inventory/hosts playbooks/windows-odj-provision.yml \
  --vault-password-file .vault_pass \
  -e odj_computer_name=PC-2026070901
```

패키지 생성 예시:

기본값은 Wazuh MSI를 `packages.wazuh.com`에서 내려받는다. 인터넷이 제한된 PC에는 `--wazuh-msi-file /secure/path/wazuh-agent-4.10.4-1.msi`로 MSI를 package에 포함한다.

```bash
./scripts/generate-windows-odj-package.sh \
  --employee-id 20260709-001 \
  --computer-name PC-2026070901 \
  --blob-file artifacts/endpoint-odj-blobs/PC-2026070901.blob \
  --wazuh-manager 192.168.0.30 \
  --wazuh-agent-version 4.10.4-1
```

사용자 PC 적용:

1. 보호된 채널로 ODJ package를 전달한다.
2. 사용자 또는 IT 담당자가 로컬 관리자 권한으로 `run-as-admin.cmd`를 실행한다.
3. 스크립트가 DNS를 설정하고 Wazuh agent 설치/서비스 시작을 검증한 뒤 ODJ를 적용한다.
4. 재부팅 후 AD 계정으로 로그인한다.
5. 실패하면 package directory, 실행 시각, 오류 메시지, 현재 DNS 설정, `WazuhSvc` 상태를 IT팀에 전달한다.

Recovery:

1. 잘못 발급되거나 유출 의심이 있는 package는 즉시 배포 경로에서 제거한다.
2. `artifacts/endpoint-odj/<employee_id>/<computer_name>/`와 임시 blob 파일의 접근 권한을 회수하거나 삭제한다.
3. AD에서 해당 computer object를 disable한다.

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool computer disable PC-2026070901"
```

4. 실제 가입이 없고 재사용 계획도 없으면 delete를 별도 승인 후 실행한다.

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool computer delete PC-2026070901"
```

5. 회수/삭제 결과를 operations DB 또는 incident/helpdesk 기록에 남긴다.


## Endpoint Asset Registration

PC 지급과 join package 발급은 asset record와 연결한다. `scripts/register-endpoint.sh`는 `computer_name`을 endpoint asset name으로 사용하고, owner를 AD username으로 기록한다. metadata에는 employee ID, department, asset tag, serial number, join method, package path, report path를 남긴다.

예시:

```bash
./scripts/register-endpoint.sh \
  --employee-id 20260710-001 \
  --username kim.chulsoo \
  --computer-name PC-2026071001 \
  --department Finance \
  --asset-tag NB-001 \
  --serial-number SERIAL1234 \
  --join-method odj \
  --package-path artifacts/endpoint-odj/20260710-001/PC-2026071001
```

기록 위치:

- Markdown report: `artifacts/endpoint-assets/<timestamp>-<computer>.md`
- Asset record: `.codex/mcp/homelab_ops.sqlite` `assets` table, kind `endpoint`
- Operation record: `.codex/mcp/homelab_ops.sqlite` `operations` table, operation type `endpoint_register`

ODJ 사용 시 raw `odj.blob` 경로가 아니라 package directory를 기록한다. `odj.blob`은 장비별 민감 자료로 취급하고 Git, Notion, Slack, raw log에 저장하지 않는다.

## ODJ Apply Test Client

ODJ 적용 검증은 workgroup 상태 Windows client가 필요하다. `win-mgmt01`은 이미 `toss.lan`에 join된 management host이므로 apply 테스트 대상으로 쓰지 않는다.

현재 기준:

- 상시 유지 Windows management VM은 `win-mgmt01` 하나로 둔다.
- ODJ apply 검증 편의를 위해 임시 Windows endpoint VM `odj-test01`을 생성했다.
  - VMID: `110`
  - CPU/RAM/Disk: 2 cores / 4096 MiB / 64G `local-lvm`
  - ISO: Windows 11 + VirtIO driver ISO attached
  - Tags: `windows;endpoint;odj-test`
  - 상태: Windows 설치 및 ODJ apply 검증 완료, QEMU Guest Agent 기준 IPv4 `192.168.0.77`
- `odj-test01`은 ODJ apply test client일 뿐 management host가 아니다.
- 테스트 VM은 GPO/drive mapping 후속 검증이 끝날 때까지 유지한다. 정리는 별도 승인 후 Terraform target destroy로 진행한다.
- 실제 ODJ blob은 Windows hostname과 AD computer object에 묶이므로, 설치 후 hostname을 발급한 ODJ computer name과 맞춘다.

`odj-test01` 검증 결과:

1. Windows hostname을 `ODJ-VERIFY01`로 맞췄다.
2. OpenSSH key auth로 automation01에서 원격 preflight를 수행했다.
3. `ODJ-VERIFY01` package를 임시 복사해 `djoin /requestODJ`를 적용했다.
4. 재부팅 후 `PartOfDomain=True`, `Domain=toss.lan`을 확인했다.
5. `nltest /dsgetdc:toss.lan`이 성공했고 AD computer object의 `lastLogon`, `operatingSystem` 값 갱신을 확인했다.
6. 적용 후 테스트 VM의 임시 ODJ package와 blob 사본은 삭제했다.

정리 절차:

```bash
terraform -chdir=terraform destroy \
  -target='module.windows_vm["odj-test01"]'
```

주의:

- `odj-test01`은 운영 VM이 아니라 검증 VM이다. 현재는 도메인 로그인, GPO, drive mapping 후속 확인을 위해 유지한다.
- ODJ blob은 다른 장비나 hostname에 재사용하지 않는다.
- 테스트 실패 또는 중단 시 package를 회수하고 AD computer object를 disable/delete한다.
- AD computer object disable/delete는 운영 변경이므로 별도 승인 후 실행한다.


## Domain Login and GPO Follow-up

ODJ 적용 후 `PartOfDomain=True`가 되어도 사용자 환경이 바로 완성되는 것은 아니다. AD 사용자 로그인, user GPO, SMB drive mapping은 별도 검증한다.

현재 `ODJ-VERIFY01` 후속 확인 기준:

- 도메인 로그인은 성공했다.
- user GPO에는 `Mapping_DriveZ`, `WallpaperPolicy`, `Screen_Lock`가 내려온다.
- computer GPO는 기본 `CN=Computers,DC=toss,DC=lan` 위치 때문에 별도 OU/link 설계가 없으면 적용되지 않을 수 있다.
- wallpaper GPO는 사용자별 로컬 경로나 mapped drive 대신 공용 읽기 가능 UNC 경로를 사용해야 한다. `Z:\toss.png`는 drive mapping 순서와 사용자 세션 상태에 의존하므로 정책 값으로 쓰지 않는다.
- `Z:` drive mapping 실패는 `storage01` Samba domain member의 winbind/idmap/SPN 상태를 먼저 확인한다.
- root 소유인 `ansible/roles/storage-policy/templates/smb.conf.j2`는 아직 직접 수정하지 못했으므로, 현 단계의 Samba idmap 적용 경로는 `ansible/playbooks/storage-domain-member.yml`이다.
- SMB/Kerberos drive mapping을 위해 `STORAGE01$`의 CIFS SPN은 `ansible/playbooks/storage-smb-spn.yml`로 관리한다.
- dc01 SYSVOL access denied가 재발하면 `samba-tool ntacl sysvolcheck`로 확인하고, 필요 시 dc01에서 `samba-tool ntacl sysvolreset`을 적용한다.
- WallpaperPolicy는 `ansible/playbooks/gpo-wallpaper-policy.yml`로 `\\storage01\shared\toss.png` UNC 경로를 관리한다. 기존 `Z:\toss.png` 값도 잘못된 값으로 보고 UNC로 되돌린다.
- WallpaperPolicy playbook은 AD metadata version을 `samba-tool gpo show`로 읽는다. `ldbmodify`가 없는 DC에서는 SYSVOL `GPT.INI`와 실제 `gpupdate` 적용은 확인할 수 있지만 AD `versionNumber` 수정은 RSAT/GPMC 또는 LDAP modify 도구가 준비된 뒤 맞춘다.

read-only 확인 명령:

```cmd
whoami
gpresult /r
net use
reg query "HKCU\Control Panel\Desktop" /v WallPaper
```

서버 쪽 확인:

```bash
ansible storage_server -i ansible/inventory/hosts -b -m command -a "testparm -s"
ansible storage_server -i ansible/inventory/hosts -b -m shell -a "wbinfo -r it.test"
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool spn list STORAGE01$"
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/storage-domain-member.yml
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/storage-smb-spn.yml
```

wallpaper가 즉시 바뀌지 않을 때는 다음을 구분한다.

- `gpupdate /force`가 성공했는지
- `reg query "HKCU\Control Panel\Desktop" /v WallPaper` 값이 `\\storage01\shared\toss.png`로 바뀌었는지
- 이미지 UNC를 현재 사용자로 직접 열 수 있는지
- Explorer가 새 wallpaper를 다시 읽도록 로그오프/로그온 또는 재부팅했는지

GPO registry 값이 맞는데 화면만 그대로면 정책 미적용이 아니라 shell refresh 문제일 수 있다. 하지만 registry 값이 `Z:\toss.png`로 남아 있으면 정책 값 자체가 잘못된 상태다.

## Endpoint Standard App Bootstrap

도메인 가입 PC에서 사용자가 앱을 설치할 때 관리자 인증이 필요한 것은 정상이다. 운영 기준은 AD `Administrator` 비밀번호를 사용자에게 입력하게 하는 것이 아니라, 승인된 표준 앱을 IT가 사전 등록하고 elevated 경로로 배포하는 것이다.

현재 bootstrap 기준:

- Catalog: `endpoint/windows/app-bootstrap/endpoint-app-catalog.json`
- Installer: `endpoint/windows/app-bootstrap/Install-EndpointApps.ps1`
- 기본 enabled 앱: `Nextcloud-33.0.7-x64.msi`, `Nextcloud.Talk-windows-x64.msi` 기반 설치
- `Nextcloud-33.0.7-x64.msi`가 Windows desktop client MSI가 맞는지 확인한다. Nextcloud server package라면 Windows endpoint 앱으로 설치하지 않는다.

IT 담당자 수동 검증:

```powershell
Set-Location \\storage01\endpoint-apps
# Files expected here:
#   Nextcloud-33.0.7-x64.msi
#   Nextcloud.Talk-windows-x64.msi
#   Install-EndpointApps.ps1
#   endpoint-app-catalog.json
Set-ExecutionPolicy -Scope Process Bypass -Force
.\Install-EndpointApps.ps1 -WhatIfOnly
.\Install-EndpointApps.ps1
```

배포 원칙:

- 사용자 PC에 shared domain admin password를 입력하지 않는다.
- 필요하면 `TOSS\Administrator` 또는 `Administrator@toss.lan` 같은 명시 형식으로 break-glass 검증만 하고, 평시 앱 설치 경로로 쓰지 않는다.
- 표준 앱은 catalog에 등록하고 detection rule을 둔다.
- 사용자에게 관리자 권한을 주지 않으려면 GPO computer startup script, scheduled task, 또는 endpoint management 도구가 SYSTEM/elevated context에서 bootstrap을 실행하게 한다.
- MSI installer를 쓸 때는 `msiexec.exe /i <MSI> /qn /norestart ALLUSERS=1`를 catalog의 `installerType=command`로 등록한다. 현재 catalog는 `\\storage01\endpoint-apps` 아래의 `Nextcloud-33.0.7-x64.msi`와 `Nextcloud.Talk-windows-x64.msi`를 기준으로 둔다.
- `ansible/playbooks/storage-endpoint-app-installers.yml`은 `/data/shared/endpoint-apps`를 만들고 같은 경로를 읽기 전용 SMB share `\\storage01\endpoint-apps`로 게시한다. `IT_Admins`에는 관리 권한, `Domain Users`와 `Domain Computers`에는 read/traverse 권한을 준다. machine account로 실행되는 SYSTEM/GPO task는 이 dedicated share를 읽고, 기존 `Z:` 공용 share 전체에 `Domain Computers` 접근을 넓히지 않는다.

2026-07-11 검증 결과:

- `ODJ-VERIFY01`에서 `NT AUTHORITY\SYSTEM` scheduled task로 `\\storage01\endpoint-apps` 접근을 확인했다. `Install-EndpointApps.ps1`, `endpoint-app-catalog.json`, 두 MSI 모두 list/read 가능하다.
- `\\storage01\shared\endpoint-apps`는 계속 실패하는 것이 정상이다. `[shared]` share는 사용자용 공용 share이며 `Domain Computers`를 열지 않는다. SYSTEM/GPO 배포는 반드시 dedicated share `\\storage01\endpoint-apps`를 사용한다.
- 같은 SYSTEM task로 `\\storage01\endpoint-apps\Install-EndpointApps.ps1`를 실행해 `Nextcloud Desktop Client`와 `Nextcloud Talk Desktop` 설치를 확인했다. detection 결과는 `C:\Program Files\Nextcloud\nextcloud.exe=True`, `C:\Program Files\Nextcloud Talk\Nextcloud Talk.exe=True`였다.
- 이 검증은 `ODJ-VERIFY01` 테스트 VM 한 대에서 수행했다. 전체 PC 배포는 OU 또는 보안 그룹으로 GPO computer startup/scheduled task 범위를 정한 뒤 적용한다.

### Endpoint App Deployment Scope

전체 도메인 PC에 바로 GPO를 연결하지 않는다. 첫 배포 scope는 AD security group `Endpoint_App_Install_Pilot`으로 제한하고, 검증된 computer account만 명시적으로 추가한다. OU 이동보다 되돌리기 쉽고, `CN=Computers`에 남아 있는 테스트 PC도 GPO security filtering으로 pilot 대상에 포함할 수 있다.

scope 준비 playbook:

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-deployment-scope.yml \
  -e '{"endpoint_app_deployment_computers":["ODJ-VERIFY01"]}'
```

이 playbook은 `Endpoint_App_Install_Pilot` 그룹을 만들고, 지정한 computer account가 존재하는지 확인한 뒤 `<COMPUTER>$` 계정을 그룹에 추가한다. AD group 생성과 membership 변경은 운영 변경이므로 실행 전 대상 computer 목록과 rollback을 확인한다.

rollback:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool group removemembers Endpoint_App_Install_Pilot ODJ-VERIFY01$"
```

GPO 또는 Scheduled Tasks preference를 만들 때는 이 그룹으로 security filtering을 걸고, computer context에서 다음 명령만 실행하게 한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\storage01\endpoint-apps\Install-EndpointApps.ps1
```

적용 후 확인:

```powershell
Test-Path 'C:\Program Files\Nextcloud\nextcloud.exe'
Test-Path 'C:\Program Files\Nextcloud Talk\Nextcloud Talk.exe'
Get-ChildItem 'C:\ProgramData\Toss\EndpointApps\Logs'
```

### Pilot Endpoint Scheduled Task

GPO security filtering을 수작업으로 바로 구성하기 전, pilot endpoint에는 직접 SYSTEM startup scheduled task를 배포해 bootstrap 동작을 검증한다. 대상은 inventory의 `windows_endpoint_pilot` group으로 제한한다. 현재 등록 대상은 `ODJ-VERIFY01` 하나다.

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-bootstrap-task.yml \
  -e endpoint_app_run_now=true
```

이 playbook은 `endpoint/windows/app-bootstrap/Configure-EndpointAppTask.ps1`를 endpoint의 `C:\ProgramData\Toss\EndpointApps\`에 복사하고, `Toss_EndpointAppBootstrap` startup task를 `SYSTEM` 계정으로 만든다. task command는 다음 경로만 실행한다.

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\storage01\endpoint-apps\Install-EndpointApps.ps1
```

2026-07-12 pilot 실행 결과:

- 대상: `ODJ-VERIFY01`
- task: `Toss_EndpointAppBootstrap`
- `lastTaskResult=0`
- detection: `NextcloudDesktop=True`, `NextcloudTalk=True`
- latest log: `C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260712-134154.log`
- 재실행 검증: `endpoint_app_run_now=false` 기준 `changed=0`, `failed=0`

rollback:

```powershell
schtasks.exe /Delete /TN Toss_EndpointAppBootstrap /F
Remove-Item -LiteralPath C:\ProgramData\Toss\EndpointApps\Configure-EndpointAppTask.ps1 -Force
```

이 방식은 pilot 검증용이다. 여러 PC로 확장할 때는 `Endpoint_App_Install_Pilot` group 기준 GPO/Scheduled Tasks preference 또는 endpoint management 도구로 전환한다.

### GPO Scheduled Task Preference Generalization

Pilot endpoint 직접 배포가 재부팅 후 ONSTART까지 검증됐으므로, 여러 PC로 확장할 때는 `Endpoint_App_Install_Pilot` security group으로 제한된 GPO Scheduled Task preference를 사용한다. 이 단계도 전체 도메인 배포가 아니라 pilot group 적용이다.

준비/dry-run:

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-gpo-scheduled-task.yml
```

기본값은 dry-run이며 AD/SYSVOL을 변경하지 않는다. 실제 적용은 다음 두 변수를 함께 명시해야 한다.

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-gpo-scheduled-task.yml \
  -e endpoint_app_gpo_apply=true \
  -e endpoint_app_gpo_security_filter_apply=true
```

`active_dc`의 local root/machine context가 GPO 생성 권한을 갖지 못하는 경우에는 RSAT/GPMC에서 domain-admin context로 생성하거나, root가 읽을 수 있는 Kerberos ccache를 active DC에 준비한 뒤 비밀번호 없는 `samba-tool` 인자를 넘긴다. 커맨드라인에 `-U user%password`, `--password`, app password, vault 값을 직접 넣지 않는다.

```bash
ansible-playbook -i ansible/inventory/hosts \
  ansible/playbooks/endpoint-app-gpo-scheduled-task.yml \
  -e endpoint_app_gpo_apply=true \
  -e endpoint_app_gpo_security_filter_apply=true \
  -e '{"endpoint_app_gpo_samba_tool_args":["--use-kerberos=required"]}' \
  -e endpoint_app_gpo_krb5ccname=FILE:/tmp/krb5cc_endpoint_gpo
```

이 playbook은 다음을 준비한다.

- GPO display name: `Endpoint_App_Bootstrap_Pilot`
- Scheduled Task preference: `Toss_EndpointAppBootstrap`
- Trigger: boot/startup
- Run as: `NT AUTHORITY\SYSTEM`
- Command: `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\storage01\endpoint-apps\Install-EndpointApps.ps1`
- Link target: `DC=toss,DC=lan`
- Security filter target: `Endpoint_App_Install_Pilot`

안전 기준:

- `endpoint_app_gpo_apply=true`만 주면 playbook은 실패한다. `endpoint_app_gpo_security_filter_apply=true` 없이는 GPO 생성/링크를 막는다.
- `endpoint_app_gpo_samba_tool_args`는 list만 허용하며 `%`와 `password` 문자열을 거부한다. 인증은 Kerberos ccache 같은 비밀번호 없는 방식으로 연결한다.
- `Authenticated Users`의 Apply Group Policy 권한을 제거하고 pilot group에 Apply Group Policy 권한을 부여한 뒤 링크하는 순서로 설계한다.
- `endpoint_app_gpo_allow_without_security_filter=true`는 의도적 broad test가 필요할 때만 사용한다.

2026-07-12 적용 시도 결과:

- `endpoint_app_gpo_apply=true`와 `endpoint_app_gpo_security_filter_apply=true`로 실제 적용을 시도했지만, `samba-tool gpo create`가 `LDAP_INSUFFICIENT_ACCESS_RIGHTS`로 실패했다.
- 실패 지점은 GPO object 생성 전 LDAP add 단계였고, GPO link나 SYSVOL ScheduledTasks.xml 작성은 실행되지 않았다.
- `samba-tool gpo listall`과 SYSVOL policy directory 확인 결과 `Endpoint_App_Bootstrap_Pilot` GPO와 잔여 directory는 남지 않았다.
- 다음 실제 적용은 RSAT/GPMC 같은 domain-admin context 또는 secrets를 저장하지 않는 검증된 `samba-tool` domain-admin 인증 경로가 준비된 뒤 진행한다.
- operations DB record: id `33`, scope `endpoint_app_gpo_scheduled_task_apply_attempt`, status `blocked`

2026-07-12 후속 보강:

- `samba-tool` 호출을 `argv` 기반으로 전환하고 optional `endpoint_app_gpo_samba_tool_args`/`endpoint_app_gpo_krb5ccname`를 추가했다.
- `ansible-playbook --syntax-check` 통과
- dry-run 결과 `changed=0`, `failed=0`
- `endpoint_app_gpo_apply=true` 단독 실행은 guard에서 `changed=0` 상태로 실패
- `-U Administrator%...` 형태의 password-bearing auth 인자는 validation에서 `changed=0` 상태로 실패
- operations DB record: id `34`, scope `endpoint_app_gpo_scheduled_task_playbook_followup`, status `success`

2026-07-12 실제 적용 결과:

- GPO GUID: `{561D8CEF-7765-4FAD-87E0-28DD3B6DC6B4}`
- `samba-tool gpo create`는 Kerberos 경로에서 SYSVOL SMB 단계가 hang되어, root-only 임시 Samba authentication file로 GPO shell을 생성한 뒤 즉시 삭제했다. 비밀번호는 출력하거나 command argument에 넣지 않았다.
- playbook으로 `ScheduledTasks.xml`, `GPT.INI`, AD `versionNumber=2`, `gPCMachineExtensionNames=[{AADCED64-746C-4633-A97C-D61349046527}{CAB54552-DEEA-4691-817E-ED4A4D1AFC72}]`, pilot Apply Group Policy ACL, domain root link를 적용했다.
- Authenticated Users의 Apply Group Policy 권한은 제거됐고 read 권한은 유지됐다. Pilot group SID `S-1-5-21-1305882574-2077486167-2475456597-2106`에 Apply Group Policy ACE를 부여했다.
- AD object는 dc01/dc02에 복제됐지만 SYSVOL은 자동 복제되지 않아, 새 GPO SYSVOL directory를 dc02에서 dc01로 `tar --xattrs --acls` 방식으로 동기화했다.
- dc01/dc02의 `GPT.INI`와 `ScheduledTasks.xml` SHA256이 일치한다.
- `ODJ-VERIFY01`에서 SYSTEM Kerberos cache purge 후 `gpupdate /target:computer /force` 성공, `gpresult`에 `Endpoint_App_Bootstrap_Pilot` 표시.
- `ODJ-VERIFY01` scheduled task 확인: `SYSTEM`, highest run level, boot trigger, action `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "\\storage01\endpoint-apps\Install-EndpointApps.ps1"`, last result `0`.
- operations DB record: id `36`, scope `endpoint_app_gpo_scheduled_task_apply`, status `success`

rollback:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool gpo dellink DC=toss,DC=lan <GPO_GUID>"

ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool gpo del <GPO_GUID>"

ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool group removemembers Endpoint_App_Install_Pilot <COMPUTER>$"
```

## SMB Department Folder ACLs

`Z:` drive는 `\\storage01\shared` 전체를 가리킨다. Nextcloud의 `/HR`, `/IT` external storage 제한은 Nextcloud 앱 내부 권한이고, Windows SMB에서 `Z:\departments`를 탐색하는 권한과는 별개다.

의도한 UX:

- `Z:\` 루트: 공용 파일과 `departments` 폴더가 보인다.
- `Z:\departments`: 부서 폴더 목록을 볼 수 있다.
- `Z:\departments\hr`: `HR_Staff`만 접근한다.
- `Z:\departments\it`: `IT_Admins`만 접근한다.
- `Z:\departments\finance`: `Finance_Staff`만 접근한다.
- `Z:\departments\security`: `Security_Team`만 접근한다.

현재 점검 결과 `departments`와 하위 폴더는 `www-data:www-data 0770`이라 SMB 도메인 사용자가 traverse할 수 없다. `ansible/playbooks/storage-department-smb-acl.yml`은 `acl` 패키지를 설치하고 POSIX ACL을 AD 그룹 기준으로 맞춘다. 이 playbook은 실제 파일 접근권한을 바꾸므로 적용 전 사용자 승인을 받는다.

## Definition of Done

v1 완료 기준:

- 사번 기반 AD Join package 생성 가능
- package에 secret 미포함
- Windows 실행 script가 관리자 권한, DNS, domain resolution을 검증
- Windows 실행 script가 Wazuh agent를 설치하고 `WazuhSvc` 시작까지 검증
- 사용자 가이드에 DNS/권한/Wazuh enrollment/재부팅/오류 보고 기준 포함
- 온보딩 workflow에서 PC AD Join과 Wazuh visibility를 같은 완료 기준으로 연결

v2 완료 기준:

- Offline Domain Join package 생성 자동화
- ODJ package가 Wazuh agent 설치와 enrollment를 기본 수행
- package 다운로드 경로 인증/인가
- SQLite operations record 저장
- Slack 알림
- Notion 운영 문서 또는 report publish
