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
