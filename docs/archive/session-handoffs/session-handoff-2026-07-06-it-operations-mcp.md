# Session Handoff - 2026-07-06 IT Operations MCP

이 문서는 `homelab-infra`의 최신 작업 상태를 다음 Codex 세션에서 바로 이어받기 위한 handoff다. 이전 handoff는 "신입사원 온보딩 v1 구현"을 다음 작업으로 남겼지만, 실제 git history 기준으로 온보딩 v1과 후속 운영 workflow는 이미 구현되어 있다.

## 현재 기준

- Repo: `/home/sysadmin/homelab-infra`
- Branch: `main`
- Worktree: handoff 갱신 전 기준 clean
- 최신 커밋: `56bb6a4 Configure Notion remote MCP`
- 최신 커밋 내용: `.codex/config.toml`에 Notion remote MCP 추가
- Notion MCP 연결 확인: `notion_fetch {"id":"self"}` 성공
- 연결된 Notion workspace: `재우 정님의 워크스페이스`

## 프로젝트 방향

이 repo의 방향은 단순한 homelab IaC가 아니라 AI/MCP 기반 IT 운영 업무 플랫폼이다.

핵심 문장:

```text
AI에게 코드 작성을 시키는 프로젝트가 아니라,
AI에게 실제 IT 운영 업무를 맡기는 프로젝트로 만든다.
```

포트폴리오 관점의 설명:

```text
AI와 MCP를 활용해 입사자 온보딩부터 검증, 보고, 문서화까지 자동화된 IT 운영 워크플로를 구축했습니다.
```

중심축은 `Samba AD -> Keycloak -> Nextcloud/Mail -> Wazuh -> Markdown/SQLite/Slack/Notion`이다. AD가 신원과 그룹의 원천이 되고, Keycloak이 SSO/IAM 레이어를 제공하며, Nextcloud/Mail이 업무 서비스를 담당하고, Wazuh와 verification workflow가 보안 가시성과 운영 증적을 남긴다.

## 최근 커밋 흐름

```text
56bb6a4 Configure Notion remote MCP
990a838 Add local secret guardrails
e88cb4f Add IT health reporting and endpoint join workflow
5d0c1d3 Add IT Manager platform roadmap and Notion publishing
395bdbb Add employee onboarding operations workflow
```

### 395bdbb - Employee onboarding operations workflow

추가/변경:

- `.codex/config.toml`
- `.codex/mcp/homelab_mcp.py`
- `AGENTS.md`
- `ansible/playbooks/employee-onboarding-verify.yml`
- `docs/operations/employee-onboarding-runbook.md`
- `docs/operations/mcp-roadmap.md`
- `scripts/onboard-employee.sh`

구현 범위:

- AD 사용자 생성 또는 보정
- 부서 기준 AD group 부여
- mail attribute 설정
- Keycloak/Nextcloud/Mail/Wazuh baseline 검증
- `artifacts/onboarding/<timestamp>-<username>.md` 리포트 생성
- `.codex/mcp/homelab_ops.sqlite` operations table 기록
- `SLACK_WEBHOOK_URL`이 있을 때 Slack 알림

### 5d0c1d3 - IT Manager platform roadmap and Notion publishing

추가/변경:

- `docs/operations/it-manager-platform-roadmap.md`
- `docs/operations/mcp-roadmap.md`
- `.codex/mcp/homelab_mcp.py`
- `.codex/config.toml`

핵심 내용:

- Identity, Collaboration, Endpoint, Alerts, Knowledge base, Helpdesk, Evidence store, Security visibility 역할 분리
- Notion publish helper 방향 정리
- Slack은 실시간 알림, Notion은 승인된 문서 축적, SQLite/Markdown은 감사 증적 저장소로 분리

### e88cb4f - IT health reporting and endpoint join workflow

추가/변경:

- `scripts/verify-and-report.sh`
- `docs/services/endpoint-management.md`
- `endpoint/windows/ad-join-self-service/Join-HomelabDomain.ps1`
- `scripts/generate-windows-ad-join-package.sh`
- `docs/getting-started/employee-it-onboarding.md`

구현 범위:

- `verify-all.yml` 실행 결과를 Markdown report로 생성
- `.codex/mcp/homelab_ops.sqlite`에 `it_health_verify` operation 기록
- Slack 알림 지원
- `--publish-notion` 옵션으로 Notion API publish 지원
- Windows AD Join self-service v1 package 생성
- AD join package에는 credential/token을 포함하지 않음

### 990a838 - Local secret guardrails

추가/변경:

- `scripts/check-no-secrets.sh`
- `.gitignore` 보강

목적:

- repo에 vault 값, token, webhook, private key, tfvars 같은 민감 파일이 들어가지 않도록 로컬 점검 경로 제공

### 56bb6a4 - Notion remote MCP

추가/변경:

- `.codex/config.toml`에 remote Notion MCP 추가

설정:

```toml
[mcp_servers.notion]
url = "https://mcp.notion.com/mcp"
startup_timeout_sec = 20
tool_timeout_sec = 60
default_tools_approval_mode = "prompt"
```

현재 세션에서 Notion MCP는 실제 사용 가능하다.

## 현재 MCP 상태

노출 확인된 MCP/tool 계열:

- `mcp__notion`
  - `notion_fetch`
  - `notion_get_teams`
  - `notion_query_database_view`
  - `notion_create_attachment`
  - 기타 page/database/comment helper
- `mcp__homelab`
  - `notion_create_page`
  - `notion_publish_project_file`

이전 기준의 `homelab`, `ansible_homelab`, `trivy`, `playwright`, `context7`, `openaiDeveloperDocs`도 프로젝트 MCP 구상에 포함된다. 공식 GitHub MCP는 Docker CLI 부재 때문에 disabled였고, GitHub 작업은 당분간 `homelab` MCP helper 또는 일반 git/SSH 경로를 사용한다.

## 중요한 문서

우선 읽을 문서:

- `AGENTS.md`
- `docs/architecture.md`
- `docs/operations/employee-onboarding-runbook.md`
- `docs/operations/it-manager-platform-roadmap.md`
- `docs/operations/mcp-roadmap.md`
- `docs/services/identity-flow.md`
- `docs/services/wazuh-siem.md`
- `docs/services/wazuh-hardening-ai-defense.md`
- `docs/services/wazuh-platform-hardening.md`
- `docs/services/nextcloud-mail.md`
- `docs/services/endpoint-management.md`

포트폴리오/Notion 글 작성 시 참고할 새 초안:

- `docs/portfolio/sme-security-infra-report.md`

## Notion 글쓰기 스타일 메모

사용자 Notion 최상위 페이지:

```text
https://app.notion.com/p/34a6d92ab08e802ab7d0f94293b1d2a3
```

확인한 구조:

- 최상위는 자기소개, 연락처, 프로젝트 목록, 진행 중인 큰 카테고리로 구성
- 프로젝트 글 제목은 `[Project XX] ...` 형식
- 첫 줄에 italic subtitle을 둠
- 문서 본문은 대체로 다음 흐름을 사용
  - `1. 개요 (Overview)`
  - `2. 문제 발견 (Problem Identification)`
  - `3. 해결 과정 (Implementation)`
  - `4. 결과 및 배움 (Result & Lessons)`
  - `5. 트러블슈팅 (Trouble Shooting)` 또는 향후 계획
- 구현 내용은 기능 나열이 아니라 문제, 임팩트, 기술적 조치, 배운 점으로 연결
- 보안 글에서는 Red Team/Blue Team, 가시성, 탐지, 대응 자동화, 운영 복구력을 강조

확인한 대표 페이지:

- `[Project 02] 리소스 최적화를 위한 Samba4 Active Directory 마이그레이션`
- `[Project 04] Wazuh SIEM 기반의 Self Red/Blue Teaming 시뮬레이션`
- `[Project 05] 회고 Phase 1: 보안 솔루션 고도화`

## 현재 인프라 핵심

### Architecture

`docs/architecture.md` 기준:

- AD Domain: `toss.lan`
- Kerberos Realm: `TOSS.LAN`
- DNS: `192.168.0.20`, `192.168.0.21`
- Nextcloud: `https://192.168.0.50`, `https://nextcloud.toss.lan`
- Keycloak Realm: `homelab`

서버 역할:

- `dc01` `192.168.0.20`: Samba additional DC, DNS, Kerberos, SYSVOL
- `dc02` `192.168.0.21`: active Samba AD DC, DNS, FSMO, Keycloak LDAP source
- `wazuh` `192.168.0.30`: Wazuh manager/dashboard
- `automation01` `192.168.0.40`: Terraform/Ansible/Git 운영 노드
- `nextcloud` `192.168.0.50`: Nextcloud/OIDC client
- `keycloak` `192.168.0.60`: Keycloak IAM, AD LDAP federation
- `storage01` `192.168.0.70`: NFS/SMB shared storage
- `mail01` `192.168.0.80`: Postfix/Dovecot, AD LDAP mail auth

### Identity/IAM

목표 흐름:

```text
Samba AD users/groups/mail/displayName
  -> Keycloak Samba-AD LDAP federation
  -> Keycloak nextcloud-oidc OIDC client
  -> groups claim
  -> Nextcloud user_oidc provider
  -> Nextcloud group provisioning / storage ACL / addressbook
```

AD 그룹:

- `HR_Staff`
- `Finance_Staff`
- `IT_Admins`
- `Security_Team`
- `Server_Admins`

Nextcloud는 OIDC `groups` claim을 기준으로 group provisioning과 external storage mount 제한을 수행한다.

### Collaboration/Mail

`Nextcloud -> Mail app -> mail01 -> AD LDAP auth` 구조다. 사용자별 IMAP 계정 비밀번호를 Ansible/Vault에 수집하지 않기 위해, IaC는 서버와 앱 연결성만 보장하고 사용자는 autoconfig를 통해 직접 Mail 앱 계정을 추가하는 기준으로 둔다.

### Wazuh/Security visibility

Wazuh는 AD, IAM, Nextcloud, Mail, Storage 계층의 보안 이벤트를 한 곳에서 수집하는 기준점이다.

수집 대상:

- `dc01`, `dc02`: journald, Samba AD 로그
- `keycloak`: journald 기반 로그인/LDAP federation 이벤트
- `nextcloud`: app log, Apache access/error, journald
- `mail01`: Postfix/Dovecot mail log, auth log, syslog
- `storage01`: Samba/SMB log, journald
- 전체 서버: package log, active response log, baseline FIM

Hardening 기준:

- Wazuh 4.10.4 component hold
- API loopback bind
- internal subnet UFW 제한
- dashboard/indexer/API TLS private key 권한 검증
- dashboard certificate rotation runbook
- RBAC: `Security_Team` analyst, `Wazuh_ReadOnly` read-only
- snapshot/restore/retention은 운영 고도화 항목

### AI Defense

`wazuh-ai-shadow.yml`은 Wazuh alerts를 읽어 SQLite WAL spool에 저장하고 deterministic enrichment를 수행한다.

중요 원칙:

- AI는 shadow mode와 비동기 분석만 수행
- Wazuh manager 수집 경로를 막지 않음
- AI 결과만으로 계정 잠금, 방화벽 차단, 파일 삭제를 실행하지 않음
- full_log, password, token, cookie, authorization, mail body는 저장/전송하지 않음
- 외부 LLM, network access, Wazuh write API, SSH/shell 권한 없음

## 검증한 것 또는 검증 경로

handoff 이전 세션에서 통과한 것으로 기록된 명령:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/ad-onboard-user.yml --syntax-check
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/verify-all.yml --syntax-check
/home/sysadmin/ai-cli/venv/bin/python -m py_compile .codex/mcp/homelab_mcp.py
codex mcp list
```

현재 세션에서 확인한 것:

```text
notion_fetch self 성공
git status --short clean
최신 커밋과 최근 5개 커밋 내용 확인
주요 docs와 scripts 내용 확인
```


## 2026-07-06 ODJ Preflight Update

사용자가 다음 구현 작업으로 Windows AD Join credential 입력을 없애는 방법을 물었고, Offline Domain Join(ODJ)을 검토했다.

현재 판정:

- Linux automation node에는 `djoin`, `samba-tool`, `net` 명령이 없다.
- apt metadata 기준 `djoin` 전용 패키지는 보이지 않았다.
- Ansible inventory에는 Windows/WinRM/RSAT management host가 없다.
- `dc02`가 현재 `active_dc`이며 FSMO/AD 쓰기 기준인 점을 전제로 확인했다.
- `dc02` SSH host key가 재구축 이후 변경되어 known_hosts mismatch가 발생했다.
  - 기존 `~/.ssh/known_hosts` line 24-26 제거
  - `ssh-keyscan -H -t ed25519,ecdsa,rsa 192.168.0.21`로 현재 key 등록
  - 원본은 `~/.ssh/known_hosts.old`에 보존됨
- `dc02`에는 `/usr/bin/samba-tool`이 있다.
- `samba-tool domain --help`에는 ODJ 전용 subcommand가 보이지 않는다.
- `samba-tool computer --help` subcommand는 `add/create/delete/edit/list/move/show`만 제공한다.
- `samba-tool computer add --help`에는 `--prepare-oldjoin` 옵션이 있지만, Windows `djoin /provision`이 생성하는 ODJ blob과 동일한 사용자 PC 무자격 증명 join package 생성 기능으로 보기는 어렵다.
- `/usr`에서 `djoin`/offline join 관련 실행 파일은 발견되지 않았다. 발견된 `offline.so`는 Samba VFS module일 뿐 ODJ 도구가 아니다.

결론:

```text
현재 Linux + Samba DC만으로 Windows Offline Domain Join blob을 바로 생성하는 경로는 확인되지 않았다.
ODJ v2의 정석 구현은 Windows management host 또는 RSAT가 설치된 Windows 관리 PC/VM이 필요하다.
```

다음 구현 목표:

1. Windows management host를 inventory에 추가할지 결정한다.
   - 후보: 기존 Windows 테스트 VM을 새로 만들거나, 관리자 PC를 WinRM으로 붙인다.
2. WinRM 연결 기준을 만든다.
   - inventory group 예: `[windows_management]`
   - 필요한 secret은 Vault/env로만 관리하고 repo에 저장하지 않는다.
3. Windows host에서 `djoin.exe /provision` 실행 가능 여부를 확인한다.
4. Linux repo에는 우선 ODJ package consumer script를 만들 수 있다.
   - `endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1`
   - `scripts/generate-windows-odj-package.sh --employee-id ... --computer-name ... --blob-file ...`
   - 이 단계는 blob을 생성하지 않고, Windows host가 만든 blob을 안전하게 package화하는 역할만 한다.
5. 실제 blob 생성 자동화는 Windows management host 연결 후 별도 playbook/script로 구현한다.

주의:

- ODJ blob은 비밀번호는 아니지만 domain join 권한을 내포한 민감 자료로 취급한다.
- package는 사용자/장비별로 만들고, 접근 제한/만료/회수 기준을 문서화해야 한다.
- 잘못 발급된 blob 또는 computer object는 disable/delete recovery 절차와 연결해야 한다.
- 기존 v1 `Join-HomelabDomain.ps1`은 credential을 script에 넣지 않는 안전한 fallback으로 유지한다.


## 2026-07-06 Windows Management VM Terraform Update

Windows Server 라이선스를 피하기 위해 Samba AD DC는 계속 Ubuntu/Samba로 유지한다. 다만 ODJ blob 생성을 위해서는 Windows `djoin.exe` 실행 환경이 필요하므로, 라이선스가 있는 Windows 11 Pro/Enterprise 관리 VM을 RSAT/djoin 전용 호스트로 추가하는 방향을 잡았다.

구현한 것:

- `terraform/modules/windows-vm` 추가
- `var.windows_vms` 추가, 기본값 `{}`
- `terraform/main.tf`에 optional `module "windows_vm"` 추가
- `terraform/terraform.tfvars.example`에 `win-mgmt01` 예시 추가
- `docs/services/endpoint-management.md`에 Windows management VM 절차 추가

검증:

- `terraform -chdir=terraform fmt -recursive` 성공
- `terraform -chdir=terraform init` 성공
- `terraform -chdir=terraform validate` 성공
- `terraform -chdir=terraform plan -refresh=false` 결과 새 Windows VM 추가는 없음. 기존 Ubuntu VM 일부의 `vm_state stopped -> running` 드리프트만 보였고 이번 변경과 직접 관련 없음.

현재 Proxmox ISO 상태:

- `local:iso/ubuntu-24.04-live-server-amd64.iso`만 확인됨
- Windows 11 ISO 없음
- VirtIO driver ISO 없음

다음 작업:

1. Proxmox `local` storage에 Windows 11 ISO 업로드
2. Proxmox `local` storage에 VirtIO driver ISO 업로드
3. local-only `terraform/terraform.tfvars`에 `windows_vms.win-mgmt01` 추가
4. `terraform plan`에서 VM 1개 생성만 보이는지 확인
5. `terraform apply` 후 Proxmox console로 Windows 설치
6. Windows VM에서 RSAT/djoin 가능 여부 확인
7. ODJ blob 생성 script/playbook 구현


## 2026-07-06 Windows Management VM Apply Update

사용자가 Windows 11 ISO와 VirtIO driver ISO를 Proxmox `local` storage에 업로드한 뒤 Terraform apply를 요청했다.

확인한 ISO:

- `local:iso/NH_SW_DVD9_Win_Pro_11_25H2.3_64BIT_Korean_Ent_MLF_X24-22925_MAK.iso`
- `local:iso/virtio-win-0.1.285.iso`

local-only `terraform/terraform.tfvars`에 아래 VM 정의를 추가했다. 이 파일은 `.gitignore` 대상이며 commit하지 않는다.

- key: `win-mgmt01`
- VMID: `109`
- CPU: 4 cores
- RAM: 8192 MiB
- Disk: 80G on `local-lvm`
- BIOS: OVMF/UEFI
- TPM: v2.0
- Network: VirtIO on `vmbr0`, firewall enabled
- ISO: Windows 11 + VirtIO driver
- Tags: `windows;management;odj`

실행 결과:

```text
terraform -chdir=terraform plan
Plan: 1 to add, 0 to change, 0 to destroy.

terraform -chdir=terraform apply -auto-approve
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

생성된 VM:

```text
VMID 109 / win-mgmt01 / running / pve01
```

Proxmox config 확인:

- `ide2`: Windows 11 ISO
- `ide3`: VirtIO driver ISO
- `scsi0`: 80G disk
- `efidisk0`: pre-enrolled keys enabled
- `tpmstate0`: TPM 2.0
- `ostype`: `win11`

주의:

- Terraform apply 중 `Qemu Guest Agent is enabled but not working` warning이 나왔다. Windows가 아직 설치되지 않았고 guest agent가 실행 중이 아니므로 현재 단계에서는 정상적으로 예상되는 경고다.
- 다음 작업은 Proxmox console에서 Windows 설치를 진행하는 것이다.
- 설치 중 디스크가 보이지 않으면 VirtIO ISO에서 storage driver를 로드한다.
- 설치 후 VirtIO guest tools/QEMU guest agent를 설치하고, RSAT/AD DS tools 또는 `djoin.exe` 사용 가능 여부를 확인한다.
- Windows 정품 인증은 사용자가 보유한 합법 라이선스와 공식 활성화 방식으로만 수행한다.


## 2026-07-06 win-mgmt01 Manual Setup Status

사용자가 Proxmox console에서 Windows 설치와 초기 설정을 진행했고, 아래 상태를 직접 확인했다.

현재 상태:

- Hostname: `WIN-MGMT01`
- IP: `192.168.0.76`
- NIC: Red Hat VirtIO Ethernet Adapter
- DHCP: enabled, DHCP server `192.168.0.1`
- DNS: currently external `168.126.63.1`, `168.126.63.2`
- QEMU Guest Agent: `Running`
- OpenSSH Server `sshd`: `Running`
- `djoin.exe`: exists at `C:\WINDOWS\system32\djoin.exe`
- RSAT AD DS/LDS Tools: `NotPresent`
- SSH firewall rules:
  - default `OpenSSH-Server-In-TCP` enabled on Private profile
  - an extra malformed/duplicate rule `OpenSSh-Server-In-TCP`` / display name `"OpenSSH Server"` exists and should be removed or replaced

Important next fixes:

1. Install RSAT AD DS/LDS Tools:

```powershell
Add-WindowsCapability -Online -Name Rsat.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0
```

2. Change DNS to AD DNS before domain/RSAT/djoin work:

```powershell
Set-DnsClientServerAddress -InterfaceAlias "이더넷" -ServerAddresses 192.168.0.21,192.168.0.20
Resolve-DnsName toss.lan
Resolve-DnsName dc02.toss.lan
```

3. Clean SSH firewall rules and restrict SSH to automation01 only:

```powershell
Remove-NetFirewallRule -Name 'OpenSSh-Server-In-TCP`' -ErrorAction SilentlyContinue
Set-NetFirewallRule -Name OpenSSH-Server-In-TCP -Profile Private -RemoteAddress 192.168.0.40
```

4. Add automation01 SSH public key to the actual Windows local admin account if remote management from Codex is needed:

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINAScdFjhSbdkcFMZ6PrdnauCizjXcIjK5HqO13HMii5 sysadmin@automation01
```

After that, Codex can SSH into `192.168.0.76` and perform validation/configuration without asking for the Windows password in chat.

## 다음에 바로 할 일

1. `docs/portfolio/sme-security-infra-report.md`를 읽고 사용자가 원하는 톤으로 다듬는다.
2. 리포트를 Notion에 publish할지 결정한다.
   - 원본 페이지 아래 새 Project 페이지로 만들 수 있다.
   - 제목 후보: `[Project 07] 중소기업형 보안 인프라 구축`
3. Notion publish 전 secret/raw log가 없는지 확인한다.
4. 필요하면 `docs/README.md`에 portfolio draft 링크를 추가한다.
5. 코드/문서 변경 후 `scripts/check-no-secrets.sh`를 실행한다.
6. 문서 변경만 있으면 적절한 커밋 메시지:

```text
Update handoff and draft SME security infra report
```

## 주의점

- `terraform.tfstate`, `terraform.tfvars`, vault 값, API token, Slack webhook, Jira token은 절대 commit하지 않는다.
- 실제 운영 변경은 승인 없이 실행하지 않는다.
- `full-apply.sh`, destructive playbook, account disable/delete, Docker restart, Proxmox power/snapshot action은 모두 승인 대상이다.
- Notion에는 secret, 임시 비밀번호, vault 값, token, webhook URL, raw sensitive log를 쓰지 않는다.
- 포트폴리오 글은 "구현했다"보다 "왜 이 설계를 했고 어떤 운영/보안 역량으로 이어졌는지"를 중심에 둔다.

## 2026-07-09 win-mgmt01 ODJ Takeover Result

사용자가 Windows VM 설치와 초기 설정을 완료한 뒤 handoff 기준으로 이어받았다.

확인 및 조치:

- `localadmin@192.168.0.76` SSH key auth를 복구했다.
  - Windows OpenSSH 관리자 계정 키는 `C:\ProgramData\ssh\administrators_authorized_keys` 기준으로 동작했다.
- `WIN-MGMT01` 상태:
  - Hostname: `WIN-MGMT01`
  - IP: `192.168.0.76`
  - RSAT AD DS/LDS Tools: `Installed`
  - DNS: `192.168.0.21`, `192.168.0.20`
  - `djoin.exe`: `C:\WINDOWS\system32\djoin.exe`
  - SSH firewall: `OpenSSH-Server-In-TCP` remote address `192.168.0.40`
- AD DNS/DC discovery 확인:
  - `Resolve-DnsName toss.lan`: `192.168.0.21`, `192.168.0.20`
  - `Resolve-DnsName dc02.toss.lan`: `192.168.0.21`
  - `nltest /dsgetdc:toss.lan`: success
- vault의 `ad_admin_password`가 `kinit Administrator@TOSS.LAN`에 통과하는 것을 확인했다.
  - secret 값은 출력하지 않았다.
- `WIN-MGMT01`을 `toss.lan` 도메인에 join했다.
  - `PartOfDomain: True`
  - AD object: `CN=WIN-MGMT01,CN=Computers,DC=toss,DC=lan`
- `ODJ-TEST01` Offline Domain Join blob 발급 성공:
  - 발급 방식: Windows Scheduled Task를 `Administrator@toss.lan` credential로 1회 실행
  - Blob path: `C:\ProgramData\homelab-odj\ODJ-TEST01.blob`
  - Blob length: `6020`
  - AD object: `CN=ODJ-TEST01,CN=Computers,DC=toss,DC=lan`
  - SPNs: `HOST/ODJ-TEST01.toss.lan`, `RestrictedKrbHost/ODJ-TEST01.toss.lan`, `HOST/ODJ-TEST01`, `RestrictedKrbHost/ODJ-TEST01`
- 임시 scheduled task는 삭제됐고, blob directory ACL은 `SYSTEM:F`, `BUILTIN\Administrators:F`만 남아 있다.
- operations DB verification records:
  - id `2`: win-mgmt01 ODJ preflight pass
  - id `3`: local workgroup context djoin failure recorded
  - id `4`: domain join and ODJ provision pass

중요 판단:

- `djoin.exe /provision`은 command-line credential 옵션이 없다.
- 로컬 `win-mgmt01\localadmin` 컨텍스트에서는 ODJ blob 발급 권한이 없어 `0x6e`로 실패했다.
- SSH 세션에서 `Start-Process -Credential`로 직접 djoin 실행은 실패했다.
- 검증된 동작 방식은 `Register-ScheduledTask -User Administrator@toss.lan -Password <vault value> -RunLevel Highest`로 1회성 task를 등록하고 즉시 실행한 뒤 삭제하는 방식이다.

다음에 바로 할 일:

1. `ODJ-TEST01.blob`을 테스트 Windows 클라이언트에 안전하게 전달하고 `djoin /requestODJ /loadfile ... /localos /windowspath C:\Windows` 적용을 검증한다.
2. 테스트 후 필요하면 `ODJ-TEST01` AD computer object를 disable/delete하는 recovery 절차를 문서화한다.
3. ODJ 자동화 스크립트/플레이북을 repo에 정식 구현한다.
   - 후보: `scripts/generate-windows-odj-package.sh`
   - 후보: `endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1`
   - 후보: Windows management host에서 scheduled task 방식으로 blob을 생성하는 Ansible playbook
4. ODJ blob은 domain join 권한을 내포한 민감 자료로 취급한다.
   - blob 자체를 Git, Notion, raw log에 저장하지 않는다.
   - 사용자/장비별 발급, 접근 제한, 만료/회수, AD computer object cleanup 기준을 같이 만든다.


## 2026-07-09 ODJ Automation and Client VM Update

이번 세션에서 handoff의 ODJ 후속 작업을 이어서 진행했다.

구현/검증 완료:

- `ansible/playbooks/windows-odj-provision.yml` 추가
  - Windows OpenSSH 기본 shell이 `cmd.exe`인 점 때문에 PowerShell은 `powershell.exe -EncodedCommand`로 명시 실행한다.
  - `win-mgmt01`에서 preflight 후 `Administrator@toss.lan` 권한의 1회성 scheduled task로 `djoin /provision`을 실행한다.
  - task와 임시 script를 삭제하고 blob ACL을 제한한다.
- `endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1` 추가
  - 사용자 PC에서 `djoin /requestODJ /loadfile ... /localos`를 실행한다.
- `scripts/generate-windows-odj-package.sh` 추가
  - fetched blob과 apply script를 package로 묶고 SQLite operations record를 남긴다.
- `ansible/inventory/hosts`에 `windows_management` group과 `win-mgmt01` 추가.
- `ODJ-VERIFY01` blob 실제 발급 성공
  - AD object: `CN=ODJ-VERIFY01,CN=Computers,DC=toss,DC=lan`
  - Blob length: `6020`
  - Local blob: `artifacts/endpoint-odj-blobs/ODJ-VERIFY01.blob`
  - Package: `artifacts/endpoint-odj/test-odj-20260709/ODJ-VERIFY01/`
  - Generated artifacts는 `.gitignore`의 `artifacts/` rule로 commit 대상에서 제외된다.
- operations DB records:
  - id `6`: ODJ automation local syntax verification
  - id `7`: `ODJ-VERIFY01` provision/package/AD object verification

테스트 client VM:

- local-only ignored file `terraform/windows-odj-client.auto.tfvars`를 생성했다.
- `terraform -chdir=terraform apply -auto-approve -target='module.windows_vm["odj-client01"]'` 실행 성공.
- 생성된 VM:
  - name: `odj-client01`
  - VMID: `110`
  - Proxmox id: `pve01/qemu/110`
  - CPU: 2 cores
  - RAM: 4096 MiB
  - Disk: 64G on `local-lvm`
  - ISO: Windows 11 + VirtIO driver ISO
  - tags: `windows;endpoint;odj-test`
- apply warning: QEMU guest agent not running. Windows가 아직 설치되지 않았으므로 현재 단계에서는 예상되는 경고다.

남은 작업:

1. Proxmox console에서 `odj-client01` Windows 설치를 완료한다.
2. VirtIO guest tools/QEMU guest agent를 설치한다.
3. 로컬 관리자 계정을 준비하고 필요하면 OpenSSH key auth를 설정한다.
4. ODJ package `artifacts/endpoint-odj/test-odj-20260709/ODJ-VERIFY01/`를 VM에 안전하게 전달한다.
5. `run-as-admin.cmd`를 관리자 권한으로 실행해 ODJ apply를 검증한다.
6. 재부팅 후 AD login, `PartOfDomain`, DNS, SPN, AD computer object 상태를 확인한다.
7. 테스트가 끝나면 `ODJ-VERIFY01` 또는 실패한 computer object cleanup 여부를 결정한다.

주의:

- `odj-client01`은 아직 Windows 설치 전이다. 지금 상태에서 Codex가 SSH/Ansible로 ODJ apply를 진행할 수 없다.
- `ODJ-VERIFY01` blob은 같은 computer name 전용이다. VM hostname을 `ODJ-VERIFY01`로 맞추거나, 다른 이름을 쓸 경우 새 blob을 발급해야 한다.
- `terraform/windows-odj-client.auto.tfvars`, `terraform.tfstate`, ODJ blob/package artifacts는 commit하지 않는다.


## 2026-07-09 ODJ Test Client Cleanup

사용자가 Windows VM 2개 상시 운용은 리소스 낭비라고 판단했고, ODJ apply 테스트는 별도 실물 노트북으로 진행하기로 했다.

정리 완료:

- `odj-client01` / VMID `110` 삭제 완료.
  - 실행: `terraform -chdir=terraform destroy -auto-approve -target='module.windows_vm["odj-client01"]'`
  - 결과: `Destroy complete! Resources: 1 destroyed.`
- `terraform/windows-odj-client.auto.tfvars` 삭제 완료.
- Terraform state 기준 Windows VM은 `win-mgmt01`만 남아 있다.

현재 기준:

- 상시 유지 Windows VM: `win-mgmt01` 1대
  - 역할: RSAT/djoin ODJ blob 발급용 management host
- ODJ apply end-to-end 테스트 대상: 사용자가 별도로 준비할 실물 Windows 노트북
- 실물 노트북 hostname은 발급한 ODJ computer name과 맞춘다.
  - 기존 test package를 쓰면 `ODJ-VERIFY01`로 맞춘다.
  - 다른 hostname을 쓸 경우 `windows-odj-provision.yml`로 새 blob을 발급한다.

남은 작업:

1. 실물 노트북을 workgroup 상태로 준비한다.
2. ODJ package를 보호된 경로로 전달한다.
3. 관리자 권한으로 `run-as-admin.cmd` 실행 후 reboot한다.
4. AD login, DNS, `PartOfDomain`, AD computer object/SPN 상태를 검증한다.
5. 테스트 완료 후 `ODJ-VERIFY01` computer object cleanup 여부를 결정한다.


## 2026-07-09 Latest Authoritative ODJ State

다음 세션은 이 섹션을 ODJ 작업의 최신 기준으로 본다. 위의 `ODJ Automation and Client VM Update`에는 `odj-client01`을 만들었던 중간 상태가 남아 있지만, 그 VM은 이후 리소스 절감을 위해 삭제됐다.

현재 최종 상태:

- 상시 Windows VM은 `win-mgmt01` 1대만 유지한다.
  - VMID: `109`
  - 역할: RSAT/djoin ODJ blob 발급용 management host
  - Domain joined: `toss.lan`
  - SSH target: `localadmin@192.168.0.76`
- `odj-client01` / VMID `110`은 삭제됐다.
  - Terraform state에도 남아 있지 않다.
  - `terraform/windows-odj-client.auto.tfvars`도 삭제됐다.
  - 다음 세션에서 이 VM을 다시 만들지 않는다.
- ODJ apply end-to-end 테스트는 사용자가 별도로 준비할 실물 Windows 노트북에서 진행한다.
- 현재 발급된 테스트 ODJ package:
  - Computer name: `ODJ-VERIFY01`
  - AD object: `CN=ODJ-VERIFY01,CN=Computers,DC=toss,DC=lan`
  - Blob length: `6020`
  - Local blob: `artifacts/endpoint-odj-blobs/ODJ-VERIFY01.blob`
  - Package: `artifacts/endpoint-odj/test-odj-20260709/ODJ-VERIFY01/`
  - `artifacts/`는 gitignored이며 blob/package는 commit하지 않는다.
- operations DB records:
  - id `6`: ODJ automation syntax/local verification
  - id `7`: `ODJ-VERIFY01` provision/package/AD object verification
  - id `8`: temporary `odj-client01` creation record, now superseded
  - id `9`: `odj-client01` cleanup record

다음에 바로 할 일:

1. 사용자가 실물 Windows 노트북을 준비하면 workgroup 상태인지 확인한다.
2. 기존 `ODJ-VERIFY01` package를 쓸 경우 노트북 hostname을 `ODJ-VERIFY01`로 맞춘다.
3. 다른 hostname을 쓸 경우 기존 blob을 재사용하지 말고 새 blob을 발급한다.

```bash
cd ansible
ansible-playbook -i inventory/hosts playbooks/windows-odj-provision.yml \
  --vault-password-file .vault_pass \
  -e odj_computer_name=<NEW-COMPUTER-NAME>
```

4. package 생성:

```bash
./scripts/generate-windows-odj-package.sh \
  --employee-id <employee-or-test-id> \
  --computer-name <COMPUTER-NAME> \
  --blob-file artifacts/endpoint-odj-blobs/<COMPUTER-NAME>.blob
```

5. package를 보호된 경로로 노트북에 전달하고 `run-as-admin.cmd`를 관리자 권한으로 실행한다.
6. 재부팅 후 AD login, DNS, `PartOfDomain`, AD computer object/SPN 상태를 검증한다.
7. 테스트 완료 또는 중단 시 `ODJ-VERIFY01`, `ODJ-TEST01` 같은 테스트 computer object를 disable/delete할지 사용자 승인 후 결정한다.

주의:

- Windows VM을 추가로 만들지 않는다. 사용자가 실물 노트북을 테스트 endpoint로 제공한다.
- `win-mgmt01`은 management host이므로 ODJ apply 테스트 대상이 아니다.
- ODJ blob은 hostname/computer object 전용이다. 다른 장비나 다른 hostname에 재사용하지 않는다.
- `terraform.tfstate`, `*.tfvars`, vault 값, ODJ blob/package artifact는 commit하지 않는다.
- 실제 AD computer object delete/disable은 운영 변경이므로 사용자 승인 후 실행한다.

검증된 명령:

```bash
ansible-playbook -i ansible/inventory/hosts ansible/playbooks/windows-odj-provision.yml \
  --syntax-check --vault-password-file ansible/.vault_pass -e odj_computer_name=ODJ-VERIFY01
bash -n scripts/generate-windows-ad-join-package.sh
bash -n scripts/generate-windows-odj-package.sh
git diff --check
terraform -chdir=terraform plan -refresh=false
```

최종 Terraform plan 기준:

```text
Plan: 0 to add, 1 to change, 0 to destroy.
```

남은 1 change는 `win-mgmt01`의 provider drift(`machine pc-q35-10.1 -> q35`, `bootdisk = scsi0`)이며, `odj-client01` 재생성 계획은 없다.


## 2026-07-10 ODJ Test VM Created

사용자가 실물 노트북 대신 임시 Windows test VM으로 ODJ apply 검증을 진행하는 방향을 승인했다.

생성한 VM:

- Terraform resource: `module.windows_vm["odj-test01"].proxmox_vm_qemu.windows_vm`
- Proxmox VMID: `110`
- Name: `odj-test01`
- Target node: `pve01`
- CPU/RAM/Disk: 2 cores / 4096 MiB / 64G `local-lvm`
- Firmware/security: OVMF, TPM 2.0
- ISO: `local:iso/NH_SW_DVD9_Win_Pro_11_25H2.3_64BIT_Korean_Ent_MLF_X24-22925_MAK.iso`
- VirtIO ISO: `local:iso/virtio-win-0.1.285.iso`
- Tags: `windows;endpoint;odj-test`
- Current status: Proxmox API reports `running`; Windows installation is not complete yet.

실행한 명령:

```bash
terraform -chdir=terraform plan -target='module.windows_vm["odj-test01"]' -out=/tmp/odj-test01-target.tfplan
terraform -chdir=terraform apply -auto-approve /tmp/odj-test01-target.tfplan
```

결과:

```text
Apply complete! Resources: 1 added, 0 changed, 0 destroyed.
```

주의:

- Full `terraform plan -refresh=false` 기준 남은 drift는 `win-mgmt01`와 `odj-test01`의 provider 표현 차이(`machine pc-q35-10.1 -> q35`, `bootdisk = scsi0`)다. 테스트 VM 생성에는 기존 VM 변경을 피하려고 targeted apply를 사용했다.
- `terraform/terraform.tfvars`는 local-only ignored file이며 `odj-test01` block이 추가되어 있다. commit하지 않는다.
- `odj-test01`은 ODJ apply test client다. `win-mgmt01`처럼 management host로 쓰지 않는다.
- Windows 설치 후 hostname을 ODJ blob의 computer name과 맞춘다. 기존 `ODJ-VERIFY01` package를 쓰려면 Windows hostname도 `ODJ-VERIFY01`이어야 한다.
- 테스트 완료 후 아래로 제거한다.

```bash
terraform -chdir=terraform destroy \
  -target='module.windows_vm["odj-test01"]'
```


## 2026-07-10 Windows Install Responsibility / Automation Note

사용자가 `odj-test01` Windows 설치를 Codex가 직접 할 수 있는지, 또는 pve01에 AI assistant를 설치하면 가능한지 질문했다.

정리한 판단:

- 현재 `odj-test01`은 OS가 설치되지 않은 빈 Windows VM이다.
- 이 단계에서는 SSH/WinRM/QEMU Guest Agent가 없으므로 Codex가 guest OS 내부 작업을 수행할 수 없다.
- Windows 초기 설치는 Proxmox noVNC console에서 사용자가 수동으로 진행해야 한다.
- 사용자가 해야 하는 최소 작업:
  1. Proxmox에서 `odj-test01` console 열기
  2. Windows 설치 시작
  3. 디스크가 안 보이면 VirtIO ISO에서 storage driver 로드
     - `odj-test01`은 Terraform 기준 `virtio-scsi-pci` + `scsi0` 디스크이므로 1순위는 `E:\vioscsi\w11\amd64`
     - VirtIO ISO가 다른 드라이브 문자로 잡히면 같은 상대 경로인 `vioscsi\w11\amd64`를 선택
     - `viostor\w11\amd64`는 VirtIO block disk일 때의 후보이며, 현재 VM 기준으로는 fallback
  4. Windows 설치 완료
  5. 로컬 관리자 계정 생성
  6. VirtIO Guest Tools / QEMU Guest Agent 설치
- 설치 완료 후 Codex가 이어받을 수 있는 기준:
  - Windows가 부팅됨
  - 네트워크가 동작함
  - QEMU Guest Agent 또는 OpenSSH/WinRM 중 하나가 준비됨
  - 이후 hostname 변경, ODJ package 전달/적용, AD login 검증은 Codex가 도울 수 있음

pve01에 AI assistant 설치 여부:

- 가능은 하지만 비추천으로 판단했다.
- 이유:
  - pve01은 hypervisor이므로 불필요한 Node/Python/browser/AI tool dependency를 늘리지 않는 것이 안전하다.
  - Proxmox root/API 권한과 AI runtime을 같은 host에 두면 보안 경계가 약해진다.
  - noVNC GUI 자동화는 화면 상태와 설치 단계 변수 때문에 안정성이 낮다.
- 권장 방향:
  - pve01은 API/Terraform으로만 제어한다.
  - 자동화는 automation01 / Codex workspace에서 수행한다.
  - 반복 테스트가 필요해지면 Windows unattended install 파이프라인을 만든다.

향후 자동화 후보:

```text
Autounattend.xml
  -> Windows answer file ISO 생성
  -> VirtIO driver 경로 지정
  -> 로컬 관리자 계정/초기 설정 자동화
  -> QEMU Guest Agent 설치
  -> 이후 SSH/WinRM 또는 guest agent로 Codex가 이어받기
```

현재 결론:

```text
이번 1회 ODJ apply 검증은 사용자가 Proxmox console에서 Windows 설치를 수동 완료한다.
그 다음부터 Codex가 원격 검증/ODJ 적용 workflow를 이어받는다.
반복 배포가 필요해지면 pve01에 AI를 설치하지 말고 Autounattend 기반 자동 설치를 구현한다.
```

## 2026-07-10 ODJ Test VM Install Complete

사용자가 `odj-test01` Windows 설치를 완료했다고 알렸고, Codex가 비파괴 조회로 현재 상태를 확인했다.

확인한 것:

- Terraform state에는 `module.windows_vm["odj-test01"].proxmox_vm_qemu.windows_vm`가 존재한다.
- VMID: `110`
- Terraform refresh-only 조회에서 QEMU Guest Agent가 IPv4 `192.168.0.77`을 보고했다.
- Terraform state 기준 NIC MAC: `bc:24:11:e9:61:83`
- ICMP ping, SSH `22`, WinRM `5985`, RDP `3389`는 automation01에서 timeout이었다.
  - Windows firewall 또는 해당 서비스 미활성 상태로 판단한다.
  - Guest Agent는 IP를 제공하므로 Windows 설치와 QEMU Guest Agent 설치는 된 것으로 본다.
- Proxmox SSH는 현재 Codex key로 접근 불가했다.
  - `root@192.168.0.200`, `sysadmin@192.168.0.200` 모두 publickey/password denied.

현재 이어받을 기준:

1. 기존 package를 재사용하려면 `odj-test01` Windows hostname을 `ODJ-VERIFY01`로 맞춘다.
2. Codex가 원격으로 계속 처리하려면 Windows에서 OpenSSH 또는 WinRM을 활성화해야 한다.
   - 권장: OpenSSH Server 설치/시작, automation01 `192.168.0.40`만 방화벽 허용.
   - 관리자 계정 SSH key는 Windows 관리자 계정 기준으로 `C:\ProgramData\ssh\administrators_authorized_keys`에 둔다.
3. 원격 접근이 없으면 Proxmox console에서 `artifacts/endpoint-odj/test-odj-20260709/ODJ-VERIFY01/` package를 전달하고 `run-as-admin.cmd`를 관리자 권한으로 실행한다.
4. 재부팅 후 AD login, DNS, `PartOfDomain`, AD computer object/SPN 상태를 검증한다.
5. 테스트 완료 후 `odj-test01` VM destroy와 `ODJ-VERIFY01` computer object cleanup 여부를 사용자 승인 후 결정한다.

## 2026-07-10 ODJ Apply Verified on Test VM

`odj-test01` Windows 설치 완료 후 ODJ package 적용까지 end-to-end 검증했다.

확인 및 조치:

- SSH key auth to `localadmin@192.168.0.77`: success
- Hostname: `ODJ-VERIFY01`
- Preflight before apply:
  - `PartOfDomain`: `False`
  - `Domain`: `WORKGROUP`
  - `djoin.exe`: present
  - DNS: `192.168.0.21`, `192.168.0.20`
- Copied package from `artifacts/endpoint-odj/test-odj-20260709/ODJ-VERIFY01/` to the VM.
- Ran `Apply-OfflineDomainJoin.ps1` with `-NoRestart`; `djoin /requestODJ` completed successfully.
- Restarted the VM.
- Verification after reboot:
  - `Name=ODJ-VERIFY01`
  - `PartOfDomain=True`
  - `Domain=toss.lan`
  - `nltest /dsgetdc:toss.lan`: success, DC discovered as `dc01.toss.lan`
  - `ipconfig /all`: DNS suffix `toss.lan`, DNS servers `192.168.0.21`, `192.168.0.20`
  - `samba-tool computer show ODJ-VERIFY01`: AD object exists, SPNs present, `lastLogon` and `operatingSystem=Windows 11 Enterprise` updated
- Removed temporary ODJ package/blob copy from the Windows test VM after apply.
- Recorded operations DB entry: `endpoint_odj_apply_verify`, target `ODJ-VERIFY01`, status `success`.

Current state:

- ODJ apply workflow is verified end-to-end on `odj-test01`.
- The test VM remains running and domain joined for any additional login/service checks.
- Cleanup still requires user approval:
  - destroy `odj-test01` with Terraform target destroy
  - decide whether to disable/delete the test AD computer object `ODJ-VERIFY01`

## 2026-07-10 ODJ Domain Join and GPO Follow-up Handoff

오늘 작업은 여기서 마무리한다. 다음 세션은 이 섹션을 ODJ/GPO troubleshooting의 최신 기준으로 본다.

완료한 것:

- `odj-test01` Windows test VM을 계속 유지하기로 결정했다.
- VM 상태:
  - Terraform resource: `module.windows_vm["odj-test01"].proxmox_vm_qemu.windows_vm`
  - VMID: `110`
  - IP: `192.168.0.77`
  - Windows hostname: `ODJ-VERIFY01`
  - Domain: `toss.lan`
  - `PartOfDomain=True`
- ODJ end-to-end 검증 완료:
  - `ODJ-VERIFY01` package를 VM에 복사해 `djoin /requestODJ` 적용 성공
  - 재부팅 후 `PartOfDomain=True`, `Domain=toss.lan` 확인
  - `nltest /dsgetdc:toss.lan` 성공, DC는 `dc01.toss.lan`로 발견
  - AD object: `CN=ODJ-VERIFY01,CN=Computers,DC=toss,DC=lan`
  - SPNs present: `HOST/ODJ-VERIFY01.toss.lan`, `RestrictedKrbHost/ODJ-VERIFY01.toss.lan`, `HOST/ODJ-VERIFY01`, `RestrictedKrbHost/ODJ-VERIFY01`
  - `operatingSystem=Windows 11 Enterprise`, `operatingSystemVersion=10.0 (26200)` 기록 확인
  - VM에 임시 복사했던 ODJ package/blob는 삭제 완료
- operations DB 기록:
  - `endpoint_odj_package`, target `ODJ-VERIFY01`, status `success`
  - `endpoint_odj_apply_verify`, target `ODJ-VERIFY01`, status `success`

사용자 로그인/GPO 확인:

- 사용자가 `it.test`로 도메인 로그인 성공했다고 보고했다.
- `query user` 결과 당시 상태:
  - `it.test`: disconnected
  - `hr.test`: active console
- `gpresult /user TOSS\it.test /r` 결과:
  - User GPO 적용 목록에 `Mapping_DriveZ`, `WallpaperPolicy`, `Screen_Lock`가 보인다.
  - 즉 user GPO가 아예 안 내려오는 상태는 아니다.
- `gpresult /scope computer` 결과:
  - Computer GPO applied list는 `N/A`
  - `ODJ-VERIFY01` computer object는 기본 `CN=Computers,DC=toss,DC=lan`에 있으므로 computer-side GPO가 필요하면 OU/link 설계를 별도로 해야 한다.

문제 증상:

- 도메인 로그인은 됐지만 바탕화면 GPO가 적용되지 않은 것처럼 보인다.
- Z: 네트워크 공유 드라이브가 자동 매핑되지 않는다.

확인한 원인 후보:

1. WallpaperPolicy 값 자체가 사용자 공용 경로가 아니다.
   - SYSVOL GPO file: `/var/lib/samba/sysvol/toss.lan/Policies/{5038E162-6AE8-4523-A8AB-129520C559EA}/User/Preferences/Registry/Registry.xml`
   - 현재 값: `C:\Users\Administrator.TOSS\Downloads\toss.png`
   - 이 경로는 `it.test`, `hr.test` 사용자 프로필에는 보통 없으므로 GPO가 적용돼도 파일을 못 찾아 바탕화면이 안 바뀔 가능성이 높다.
   - 다음 수정 방향: wallpaper 파일을 `\\toss.lan\SYSVOL\toss.lan\wallpaper\toss.png` 같은 공용 읽기 가능 경로에 두고 GPO 값을 그 UNC 경로로 바꾼다.

2. Mapping_DriveZ는 GPO가 내려왔지만 Drive Maps processing이 실패했다.
   - SYSVOL GPO file: `/var/lib/samba/sysvol/toss.lan/Policies/{807F7829-764A-495B-A4A3-81D4B282225A}/User/Preferences/Drives/Drives.xml`
   - 현재 mapping: `Z:` -> `\\storage01\shared`
   - Windows Application log:
     - Source: `Group Policy Drive Maps`
     - Event ID: `4098`
     - Error: `0x80070056`, Korean message meaning the specified network password is not correct
     - GPO: `Mapping_DriveZ {807F7829-764A-495B-A4A3-81D4B282225A}`
   - Client DNS/SMB reachability is OK:
     - `Resolve-DnsName storage01.toss.lan` -> `192.168.0.70`
     - `Test-NetConnection storage01.toss.lan -Port 445` -> `TcpTestSucceeded=True`
   - storage01 domain member trust is OK:
     - `net ads testjoin` -> `Join is OK`
     - `wbinfo -t` -> trust secret succeeded
   - But storage01 winbind group lookup fails:
     - `wbinfo -r it.test` -> `WBC_ERR_DOMAIN_NOT_FOUND`
     - `wbinfo --group-info 'Domain Users'` -> `WBC_ERR_DOMAIN_NOT_FOUND`
   - `testparm -s` warns:
     - `idmap range not specified for domain '*'`
     - `ERROR: Invalid idmap range for domain *!`
   - `STORAGE01$` AD computer object currently has only HOST SPNs:
     - `HOST/STORAGE01.toss.lan`
     - `RestrictedKrbHost/STORAGE01.toss.lan`
     - `HOST/STORAGE01`
     - `RestrictedKrbHost/STORAGE01`
   - Missing CIFS SPNs are a strong candidate for SMB/Kerberos drive mapping problems:
     - `CIFS/storage01`
     - `CIFS/storage01.toss.lan`

Important commands already run/read-only:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool computer show ODJ-VERIFY01"
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool gpo listall"
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool gpo show {5038E162-6AE8-4523-A8AB-129520C559EA}"
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool gpo show {807F7829-764A-495B-A4A3-81D4B282225A}"
ansible storage_server -i ansible/inventory/hosts -b -m command -a "net ads testjoin"
ansible storage_server -i ansible/inventory/hosts -b -m command -a "wbinfo -t"
ansible storage_server -i ansible/inventory/hosts -b -m command -a "testparm -s"
ssh -o BatchMode=yes localadmin@192.168.0.77 gpresult /user TOSS\\it.test /r
ssh -o BatchMode=yes localadmin@192.168.0.77 wevtutil qe Application /q:"*[System[(EventID=4098)]]" /c:20 /rd:true /f:text
ssh -o BatchMode=yes localadmin@192.168.0.77 query user
```

다음 세션에서 바로 할 일:

1. 사용자에게 현재 콘솔에서 실제 로그인 사용자를 확인하게 하거나 원격에서 다시 확인한다.

```cmd
whoami
gpresult /r
net use
reg query "HKCU\Control Panel\Desktop" /v WallPaper
```

2. WallpaperPolicy 수정 설계를 한다.
   - 공용 wallpaper 파일 경로를 정한다.
   - 추천: SYSVOL 아래 읽기 전용 경로.
   - GPO Registry.xml 값을 `C:\Users\Administrator.TOSS\Downloads\toss.png`에서 공용 UNC로 바꾼다.
   - 이 변경은 GPO 운영 변경이므로 적용 전 사용자 승인 필요.

3. storage01 Samba domain member 설정을 보강한다.
   - `ansible/roles/storage-policy/templates/smb.conf.j2` 현재 상태는 idmap 설정이 없다.
   - 다음 후보 설정을 검토한다:
     - `idmap config * : backend = tdb`
     - `idmap config * : range = 3000-7999`
     - `idmap config TOSS : backend = rid`
     - `idmap config TOSS : range = 10000-999999`
     - 필요 시 `template shell`, `template homedir`
   - `valid users = @"Domain Users"`, `force group = "Domain Users"`가 winbind group resolution에 의존하므로 group lookup 정상화가 필요하다.
   - 변경 후 `testparm -s`, `systemctl restart smbd winbind`, `wbinfo -r it.test`, `wbinfo --group-info 'TOSS\\Domain Users'` 또는 적절한 이름으로 검증한다.

4. SMB SPN 추가 여부를 결정한다.
   - 후보:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool spn add CIFS/storage01 STORAGE01$"
ansible active_dc -i ansible/inventory/hosts -b -m command \
  -a "samba-tool spn add CIFS/storage01.toss.lan STORAGE01$"
```

   - 이건 AD 변경이므로 사용자 승인 후 실행한다.
   - 추가 후 `samba-tool spn list STORAGE01$`로 확인한다.

5. 클라이언트에서 정책 재적용/재로그온 검증.

```cmd
gpupdate /force
logoff
```

   - 다시 로그인 후:

```cmd
whoami
gpresult /r
net use
reg query "HKCU\Control Panel\Desktop" /v WallPaper
```

주의:

- `odj-test01`은 계속 유지한다. destroy하지 않는다.
- `ODJ-VERIFY01` AD computer object도 지금은 cleanup하지 않는다.
- GPO 수정, AD SPN 추가, storage01 Samba config 변경/restart는 운영 변경이므로 다음 세션에서 사용자 승인 후 진행한다.
- ODJ blob/package 원문은 Git/Notion/raw log에 남기지 않는다.

## 2026-07-10 Storage SMB/GPO Follow-up Progress

ODJ 후속 GPO/drive mapping troubleshooting을 이어서 진행했다.

확인한 것:

- `ODJ-VERIFY01`에 SSH로 접속하면 현재 remote shell 사용자는 `ODJ-VERIFY01\localadmin`이다.
- localadmin 기준 `gpresult /r`은 domain user RSoP가 없어 유효하지 않다. 실제 GPO 검증은 콘솔에서 `it.test` 또는 대상 domain user로 다시 로그인해 확인해야 한다.
- storage01 live Samba config에는 `idmap config * : backend = tdb`만 있고 range가 없어 `testparm -s`가 `idmap range not specified for domain '*'`를 경고했다.
- `wbinfo -r it.test`, `wbinfo --group-info TOSS\Domain Users`, `wbinfo --group-info Domain Users`가 실패했다.
- `STORAGE01$`에는 HOST SPN만 있었고 `CIFS/storage01`, `CIFS/storage01.toss.lan`이 없었다.

적용한 것:

- `ansible/playbooks/storage-domain-member.yml` 추가 및 적용.
  - `/etc/samba/smb.conf`에 Ansible managed block으로 `winbind refresh tickets`, template shell/homedir, idmap default range, `TOSS` rid range를 추가했다.
  - `smbd`, `winbind`를 재시작했다.
  - 적용 후 `testparm -s`의 idmap range 오류가 사라졌다.
  - `wbinfo -r it.test`와 `Domain Users` group lookup이 성공했다.
- `ansible/playbooks/storage-smb-spn.yml` 추가 및 적용.
  - `STORAGE01$`에 `CIFS/storage01`, `CIFS/storage01.toss.lan` SPN을 추가했다.
  - playbook assertion으로 두 SPN 존재를 확인했다.
- 문서 갱신:
  - `docs/services/endpoint-management.md`에 ODJ 후속 GPO/drive mapping 기준과 두 playbook 적용 경로를 추가했다.
  - `docs/operations/helpdesk-scenarios.md`에 `windows-gpo` scenario를 추가했다.

주의:

- `ansible/roles/storage-policy/templates/smb.conf.j2`와 handler는 root 소유라 현재 세션에서 직접 수정하지 못했다. 현 단계의 반복 적용 경로는 새 playbook 두 개다. 나중에 sudo 가능한 세션에서 role template과 handler에 흡수하는 것이 좋다.
- WallpaperPolicy의 잘못된 로컬 경로 문제는 아직 수정하지 않았다. 다음 수정 방향은 wallpaper 파일을 SYSVOL 공용 UNC 경로로 옮기고 GPO Registry.xml 값을 해당 UNC로 바꾸는 것이다.

다음에 바로 할 일:

1. `ODJ-VERIFY01` 콘솔에서 `it.test`로 새 로그인하거나 재로그온한다.
2. 사용자 세션에서 아래를 확인한다.

```cmd
whoami
gpresult /r
net use
reg query "HKCU\Control Panel\Desktop" /v WallPaper
```

3. `Z:` drive mapping이 여전히 실패하면 Windows Application log의 Group Policy Drive Maps `4098` 최신 이벤트를 다시 본다.
4. wallpaper가 여전히 기본값이면 SYSVOL wallpaper UNC 경로 설계 후 GPO 값을 수정한다.

## 2026-07-10 GPO Apply Verified on ODJ-VERIFY01

ODJ 후속 GPO/drive mapping 검증을 끝까지 진행했다.

추가로 확인한 것:

- `ODJ-VERIFY01` 현재 세션:
  - `hr.test`: active console
  - `it.test`: disconnected
- `hr.test`와 `it.test` 사용자 hive 모두 기존 Wallpaper 값이 `C:\Users\Administrator.TOSS\Downloads\toss.png`였다.
- `hr.test` 사용자 hive에는 `HKCU\Network\Z`가 없었다.
- `hr.test` interactive scheduled task로 확인한 결과:
  - `\\storage01\shared`와 `\\storage01.toss.lan\shared`는 접근 성공
  - `\\toss.lan\SysVol\...\GPT.INI`와 `\\dc01.toss.lan\SysVol\...\GPT.INI`는 Access denied
  - `\\dc02.toss.lan\SysVol\...\GPT.INI`는 접근 성공
- `ODJ-VERIFY01`은 `nltest /dsgetdc:toss.lan`에서 `dc01.toss.lan`을 선택하고 있었다.

수정한 것:

- `dc01` SSH host key mismatch를 정리했다.
  - `ssh-keygen -R 192.168.0.20`
  - `ssh-keyscan -H -t ed25519,ecdsa,rsa 192.168.0.20 >> ~/.ssh/known_hosts`
- `dc01`에서 `samba-tool ntacl sysvolreset` 실행.
  - 이후 `hr.test`가 `\\toss.lan\SysVol`와 `\\dc01.toss.lan\SysVol`의 `GPT.INI`를 읽을 수 있게 됐다.
- `ansible/playbooks/gpo-wallpaper-policy.yml` 추가 및 적용.
  - WallpaperPolicy Registry.xml 값을 `\\storage01\shared\toss.png`로 변경했다.
  - 양쪽 DC의 `GPT.INI` version을 `1245196`으로 갱신했다.
  - `ldbmodify`가 없어 AD `versionNumber` metadata는 갱신하지 못했다. 다만 `gpupdate /force`로 실제 적용은 검증했다.

최종 검증:

- `hr.test` interactive context에서 `gpupdate /target:user /force` 성공.
- `net use` 결과:
  - `Z:` -> `\\storage01\shared` OK
- `HKCU\Network\Z` registry 생성 확인:
  - `RemotePath=\\storage01\shared`
- `HKCU\Control Panel\Desktop\WallPaper` 확인:
  - `\\storage01\shared\toss.png`
- 검증용 temporary scheduled tasks/files는 삭제했다.

남은 주의점:

- WallpaperPolicy AD metadata version은 `samba-tool gpo show` 기준 아직 `1179660`으로 보일 수 있다. dc02에 `ldbmodify`가 없어 자동 갱신하지 못했다. 현재는 `gpupdate /force`로 적용 확인됐지만, 장기적으로는 RSAT/GPMC 또는 Samba LDAP modify 도구가 있는 환경에서 AD `versionNumber`를 SYSVOL `GPT.INI` version과 맞추는 것이 좋다.
- `ansible/roles/storage-policy/templates/smb.conf.j2`는 root 소유라 아직 role에 통합하지 못했다. 현재 반복 적용 경로는 standalone playbook들이다.

## 2026-07-10 Endpoint Apps and SMB Department ACL Handoff

사용자가 "관리자 권한이 안 되니 다음에 하자"고 중단했다. 다음 세션은 여기서 이어받는다.

사용자 의도:

- 조인된 Windows PC에서 일반 사용자가 관리자 비밀번호를 입력하지 않고 표준 앱을 설치하게 하고 싶다.
- 설치 대상 MSI는 storage01에 올려 둔 두 파일이다.
  - `Nextcloud-33.0.7-x64.msi`
  - `Nextcloud.Talk-windows-x64.msi`
- `Z:` drive는 공용 루트로 쓰고, `Z:\departments` 아래는 부서별 폴더만 해당 부서 사용자가 접근하게 하고 싶다.
  - `Z:\departments\hr`: `HR_Staff`
  - `Z:\departments\it`: `IT_Admins`
  - `Z:\departments\finance`: `Finance_Staff`
  - `Z:\departments\security`: `Security_Team`

적용 완료:

- `ansible/playbooks/storage-department-smb-acl.yml` 추가 및 적용.
  - `acl` 패키지 설치.
  - `/data/shared/departments`는 `Domain Users`가 list/traverse 가능.
  - 각 부서 폴더는 해당 AD 그룹만 `rwx`.
  - 재실행 `changed=0` 확인.
- 실제 접근 검증:
  - `hr.test`: `departments`와 `departments/hr` OK, `it/finance/security` DENY.
  - `it.test`: `departments`와 `departments/it` OK, `hr/finance/security` DENY.
- `ansible/playbooks/storage-endpoint-app-installers.yml` 추가 및 적용.
  - `\\storage01\shared\endpoint-apps`를 준비.
  - `IT_Admins`: 관리 권한.
  - `Domain Users`, `Domain Computers`: read/traverse 권한.
  - `Install-EndpointApps.ps1`와 `endpoint-app-catalog.json`를 SMB 폴더에 배포.
  - MSI 두 개가 해당 폴더에서 발견됨:
    - `/data/shared/endpoint-apps/Nextcloud-33.0.7-x64.msi`
    - `/data/shared/endpoint-apps/Nextcloud.Talk-windows-x64.msi`
  - 재실행 `changed=0` 확인.
- `endpoint/windows/app-bootstrap/endpoint-app-catalog.json`은 UNC MSI 경로를 사용한다.
  - `\\storage01\shared\endpoint-apps\Nextcloud-33.0.7-x64.msi`
  - `\\storage01\shared\endpoint-apps\Nextcloud.Talk-windows-x64.msi`
- `docs/services/endpoint-management.md`에 endpoint app bootstrap과 SMB department ACL 운영 기준을 추가했다.

중요한 운영 판단:

- 사용자가 `\\storage01\shared\endpoint-apps`를 읽을 수 있어도 MSI 설치는 관리자 권한이 필요하다.
- 폴더 권한을 "관리자 권한으로 열어주는" 식으로는 해결되지 않는다. 설치 elevation은 Windows 실행 토큰 문제다.
- 사용자가 관리자 비밀번호를 모르는 상태에서 설치하려면 다음 중 하나가 필요하다.
  1. 이미 관리자 권한을 가진 원격 관리 세션에서 `SYSTEM` scheduled task로 설치 실행.
  2. GPO computer startup script 또는 Scheduled Tasks preference로 `SYSTEM` 컨텍스트에서 설치 실행.
  3. 향후 endpoint management 도구를 도입해 SYSTEM/elevated context로 배포.

중단된 작업:

- `ODJ-VERIFY01`에 SSH로 접근 가능한지 확인했다.
  - `localadmin@192.168.0.77` SSH 접속은 됐다.
  - `whoami`: `odj-verify01\localadmin`.
  - `localadmin` 컨텍스트에서 `\\storage01\shared\endpoint-apps\Install-EndpointApps.ps1` 접근은 `Access denied`였다. 이는 local account라 도메인 SMB 자격이 없기 때문으로 정상적인 설명이다.
- 그 다음 `SYSTEM` scheduled task가 `Domain Computers` 권한으로 SMB share를 읽을 수 있는지 임시 검증하려 했다.
  - 첫 시도는 quoting 오류로 실패했고 task는 삭제됐다.
  - 두 번째 시도는 임시 PowerShell driver를 `/tmp`에서 만들고 `scp`/`ssh`로 실행하려던 중 사용자가 중단했다.
  - 설치 명령은 실행하지 않았다. 다만 중단 시점에 따라 `ODJ-VERIFY01`에 아래 임시 파일 일부가 남았을 수 있으니 다음 세션에서 먼저 확인/삭제한다.

다음 세션 첫 점검:

```powershell
# ODJ-VERIFY01에서 localadmin 또는 원격 관리 세션으로 확인
Get-ChildItem C:\ProgramData\Toss\EndpointApps -Force -ErrorAction SilentlyContinue
schtasks /Query /TN TossEndpointShareTest 2>$null
schtasks /Delete /TN TossEndpointShareTest /F 2>$null
Remove-Item C:\ProgramData\Toss\EndpointApps\system-share-test* -Force -ErrorAction SilentlyContinue
Remove-Item C:\ProgramData\Toss\EndpointApps\system-share-test-driver.ps1 -Force -ErrorAction SilentlyContinue
```

다음에 바로 할 일:

1. `ODJ-VERIFY01`에서 `SYSTEM` 컨텍스트가 `\\storage01\shared\endpoint-apps`를 읽을 수 있는지 검증한다.
   - 성공 기준: SYSTEM task에서 `Test-Path '\\storage01\shared\endpoint-apps\Install-EndpointApps.ps1'`가 `True`.
2. 검증이 성공하면 같은 방식으로 SYSTEM task에서 아래 설치를 실행한다.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\\\storage01\shared\endpoint-apps\Install-EndpointApps.ps1
```

3. 설치 후 확인:

```powershell
Test-Path "$env:ProgramFiles\Nextcloud\nextcloud.exe"
Test-Path "$env:ProgramFiles\Nextcloud Talk\Nextcloud Talk.exe"
Get-ChildItem C:\ProgramData\Toss\EndpointApps\Logs -ErrorAction SilentlyContinue
```

4. 실제 설치가 확인되면 GPO computer startup 방식으로 일반화한다.
   - 현재 `ODJ-VERIFY01` computer object는 기본 `CN=Computers,DC=toss,DC=lan`에 있다.
   - computer-side GPO를 안정적으로 적용하려면 OU/link 설계를 먼저 해야 한다.
   - 임시로 개별 PC에만 적용할지, 도메인 전체/OU에 적용할지 사용자 확인 필요.

검증 완료 기록:

- `storage-department-smb-acl.yml --syntax-check` 통과.
- `storage-department-smb-acl.yml` 재실행 `changed=0`.
- `storage-endpoint-app-installers.yml --syntax-check` 통과.
- `storage-endpoint-app-installers.yml` 재실행 `changed=0`.
- endpoint app catalog JSON validation 통과.
- `scripts/check-no-secrets.sh` 통과.
- `git diff --check` 통과.
- operations DB:
  - `id=24`: SMB department ACL 및 storage01-hosted Nextcloud MSI 설치 경로 준비 기록.


## 2026-07-11 Endpoint App SYSTEM Install Fix

이전 세션은 `ODJ-VERIFY01`에서 SYSTEM scheduled task가 `\\storage01\shared\endpoint-apps`를 읽을 수 있는지 검증하려던 중 중단됐다. 이어받은 결과, 원인은 installer 파일 권한이 아니라 SMB share 경로 설계였다.

확인한 문제:

- `ODJ-VERIFY01`의 `localadmin` 원격 SSH는 정상이다.
- 남아 있던 임시 파일 `system-share-test-result.txt`, `system-share-test.cmd`는 정리했다.
- SYSTEM scheduled task는 정상 실행됐지만 처음에는 두 경로 모두 실패했다.
- storage01 live Samba config에서 `[shared]`는 `valid users = @"Domain Users"`만 허용했다.
- `Domain Computers` group lookup과 `/data/shared/endpoint-apps` POSIX ACL은 정상이었다.
- `ansible/playbooks/storage-endpoint-app-installers.yml`의 `[endpoint-apps]` block이 live config에 반영되지 않은 상태였고, catalog도 사용자용 `\\storage01\shared\endpoint-apps` MSI 경로를 가리켰다.

수정한 것:

- `endpoint/windows/app-bootstrap/endpoint-app-catalog.json`의 MSI 경로를 dedicated share 기준으로 변경했다.
  - `\\storage01\endpoint-apps\Nextcloud-33.0.7-x64.msi`
  - `\\storage01\endpoint-apps\Nextcloud.Talk-windows-x64.msi`
- `ansible/playbooks/storage-endpoint-app-installers.yml --syntax-check` 통과.
- `ansible-playbook -i ansible/inventory/hosts ansible/playbooks/storage-endpoint-app-installers.yml` 적용.
  - `[endpoint-apps]` share가 live config에 추가됐다.
  - `valid users = @"Domain Users" @"Domain Computers" @IT_Admins`
  - `smbd` restart 완료.
- `ODJ-VERIFY01` SYSTEM task 검증:
  - `\\storage01\shared\endpoint-apps`는 실패. 정상이다. `[shared]`는 사용자용 share라 computer account를 열지 않는다.
  - `\\storage01\endpoint-apps`는 성공.
  - `Install-EndpointApps.ps1`, `endpoint-app-catalog.json`, `Nextcloud-33.0.7-x64.msi`, `Nextcloud.Talk-windows-x64.msi` list/read 확인.
- `ODJ-VERIFY01` 한 대에서 SYSTEM scheduled task로 실제 설치 검증 완료.
  - 실행 script: `\\storage01\endpoint-apps\Install-EndpointApps.ps1`
  - identity: `nt authority\system`
  - `Nextcloud Desktop Client` install success
  - `Nextcloud Talk Desktop` install success
  - detection:
    - `C:\Program Files\Nextcloud\nextcloud.exe=True`
    - `C:\Program Files\Nextcloud Talk\Nextcloud Talk.exe=True`
  - log: `C:\ProgramData\Toss\EndpointApps\Logs\endpoint-apps-20260711-204455.log`
- VM에 복사했던 임시 driver/runner scripts는 삭제했다. 결과 파일과 설치 log는 증적으로 남겼다.
- `docs/services/endpoint-management.md`에 2026-07-11 검증 결과와 dedicated share 기준을 추가했다.

중요한 운영 기준:

- 일반 사용자가 MSI를 직접 실행하면 관리자 인증을 요구하는 것이 정상이다.
- 비밀번호 없는 표준 앱 설치는 사용자가 직접 설치하는 UX가 아니라, 컴퓨터가 SYSTEM/elevated context에서 설치하는 배포 UX로 처리한다.
- 오늘 실제 설치는 `ODJ-VERIFY01` 테스트 VM 한 대에만 수행했다.
- 전체 PC 배포는 아직 하지 않았다. OU 또는 보안 그룹으로 GPO computer startup/scheduled task scope를 정한 뒤 적용한다.
- 전체 배포 시에도 `\\storage01\shared\endpoint-apps`가 아니라 `\\storage01\endpoint-apps`를 사용한다.

다음에 바로 할 일:

1. 전체 도메인 PC에 배포할지, `ODJ-VERIFY01` 같은 테스트 OU/보안 그룹에만 배포할지 scope를 정한다.
2. computer-side GPO를 안정적으로 적용하려면 endpoint computer objects를 OU로 이동하거나 security filtering group을 만든다.
3. GPO computer startup script 또는 scheduled task preference가 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File \\storage01\endpoint-apps\Install-EndpointApps.ps1`를 SYSTEM으로 실행하게 한다.
4. 배포 후 각 PC에서 detection path와 `C:\ProgramData\Toss\EndpointApps\Logs`를 확인한다.
