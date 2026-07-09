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

예시:

```bash
./scripts/generate-windows-ad-join-package.sh   --employee-id 20260706-001   --computer-name PC-20260706001
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

## Definition of Done

v1 완료 기준:

- 사번 기반 AD Join package 생성 가능
- package에 secret 미포함
- Windows 실행 script가 관리자 권한, DNS, domain resolution을 검증
- 사용자 가이드에 DNS/권한/재부팅/오류 보고 기준 포함
- 온보딩 workflow에서 PC AD Join 수동 후속 작업으로 연결

v2 완료 기준:

- Offline Domain Join package 생성 자동화
- package 다운로드 경로 인증/인가
- SQLite operations record 저장
- Slack 알림
- Notion 운영 문서 또는 report publish
