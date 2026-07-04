# Session Handoff - 2026-07-04

이 문서는 다음 작업 세션에서 현재 상태를 빠르게 이어받기 위한 요약이다. 기준 repo는 `/home/sysadmin/homelab-infra`이며 remote는 `git@github.com:JamieJai/sme-security-infra.git`이다.

## 목표

`sme-security-infra`를 소규모/중소기업용 오픈소스 보안 인프라 템플릿으로 완성한다. 핵심 흐름은 다음과 같다.

```text
Terraform VM provisioning
  → Ansible OS/service/security configuration
  → Samba AD identity source
  → Keycloak IAM/SSO
  → Nextcloud cloud/collaboration/mail/talk portal
  → storage01 shared storage
  → mail01 Postfix/Dovecot backend
  → Wazuh SIEM/XDR
  → later AI-assisted detection/triage
```

## 오늘 완료한 주요 작업

### 1. Nextcloud cron 및 AD DC 시간 동기화 안정화

커밋: `dcd6f7d Stabilize Nextcloud cron and AD DC time sync`

- `nextcloud`에 cron 설치/활성화
- `www-data` crontab에 Nextcloud background job 등록
- `dc01`, `dc02` chrony 정책 분리
  - `dc01 → dc02`
  - `dc02 → ntp.ubuntu.com`
- 검증 결과:
  - Nextcloud background mode: `cron`
  - DC 양쪽 `NTPSynchronized=yes`

### 2. DC에서 SSSD 비활성화

커밋: `b4cb0f7 Disable SSSD on Samba AD domain controllers`

- DC는 Samba AD/DNS/Kerberos에 집중하도록 SSSD 비활성화
- `dc01`, `dc02`에서 SSSD service/socket stop/disable/mask
- Samba AD DC 서비스 active, replication `[ALL GOOD]` 확인

설계 결정:

- DC에는 SSSD를 쓰지 않는다.
- 일반 Linux member server에서만 SSSD/AD join을 사용한다.
- 직원 주소록은 SSSD가 아니라 AD `mail/displayName/sAMAccountName` → Nextcloud addressbook sync로 처리한다.

### 3. Storage, Nextcloud Talk, 초기 구축 가이드 정리

커밋: `2a8e3aa Add collaboration and build runbooks`

- `storage01`에서 Kerberized NFS를 쓰지 않는 현재 기준으로 `rpc-svcgssd` 비활성화
- Nextcloud Talk 설치/활성화
- 초기 구축 가이드 추가: `docs/initial-build-guide.md`
- 중복 루트 playbook 제거 및 `ansible/playbooks/` 기준으로 정리

검증 결과:

- 전체 failed systemd unit 없음
- Nextcloud Talk enabled
- NFS/SMB active

### 4. Nextcloud Mail 연동

커밋: `46f3b48 Add Nextcloud Mail integration runbook`

- `playbooks/nextcloud-mail.yml` 추가
- Nextcloud Mail 앱 enabled
- Nextcloud 시스템 SMTP 설정: `mail01.toss.lan:25`
- Nextcloud에서 mail01 25/587/993 접근 검증
- `docs/nextcloud-mail.md` 추가

설계 결정:

- 사용자별 Nextcloud Mail 계정 자동 등록은 하지 않는다.
- IMAP 계정 등록에는 사용자 비밀번호가 필요하므로 IaC/Vault에 사용자 비밀번호를 모으지 않는다.
- 사용자는 autoconfig를 통해 직접 연결한다.

### 5. Wazuh agent/log 수집 표준화

커밋: `1db7212 Standardize Wazuh agent log collection`

- `wazuh-agent-deploy.yml`을 `ansible/playbooks/`로 이동
- `playbooks/wazuh-agent-logs.yml` 추가
- 역할별 로그 수집 설정 추가
  - DC: Samba AD logs
  - storage01: Samba/SMB logs
  - nextcloud: Nextcloud app log, Apache logs
  - mail01: mail/auth/syslog
  - keycloak: journald 기준 유지
- `docs/wazuh-siem.md` 추가

검증 결과:

- 모든 Wazuh agent active
- Wazuh manager의 `agent_control -lc`에서 전체 Active
- 전체 failed unit 없음

### 6. AD → Keycloak → Nextcloud identity flow 검증

커밋: `3254957 Add identity flow verification runbook`

- `playbooks/identity-flow-verify.yml` 추가
- `docs/identity-flow.md` 추가
- 검증 항목:
  - Keycloak realm `homelab` enabled
  - LDAP federation `Samba-AD` 존재
  - OIDC client `nextcloud-oidc` 정상
  - groups claim mapper `nextcloud-groups` 정상
  - Nextcloud OIDC provider group provisioning enabled
  - group whitelist/restrict login enabled
  - 부서별 external storage ACL 정상
  - system addressbook exposed true

현재 AD/Nextcloud 테스트 사용자 상태:

- `HR_Staff`: `hr.test`
- `IT_Admins`: `it.test`

### 7. 레거시/위험 playbook 정리

커밋: `3d36b65 Archive legacy Ansible playbooks`

- 레거시 playbook archive 이동:
  - `ansible/archive/legacy/keycloak-deploy.yml`
  - `ansible/archive/legacy/keycloak-sso-setup.yml`
  - `ansible/archive/legacy/mail-server.yml`
- `docs/ansible-playbook-catalog.md` 추가
- 전체 `site.yml`, `playbooks/*.yml` syntax 통과 확인

중요한 분류:

- 운영 기준 playbook은 `ansible/playbooks/` 아래에 둔다.
- 위험/복구 playbook은 무심코 실행하지 않는다.
  - `playbooks/nextcloud-server.yml`
  - `playbooks/rebuild-dc01.yml`
  - `playbooks/additional-dc.yml`
  - `playbooks/ad-server.yml`
  - `playbooks/repair-nextcloud-config.yml`
  - `playbooks/ad-dc-failover-test.yml`

### 8. Terraform 운영 기준 정리

커밋:

- `b869782 Document Terraform operating baseline`
- `7b52b5d Format Terraform Ubuntu VM module`

처리 내용:

- 잘못 생성되어 있던 `terraform/.git` 제거
- Terraform 민감 파일 권한 `600` 적용
  - `terraform.tfvars`
  - `terraform.tfstate`
  - `terraform.tfstate.backup`
- `docs/terraform-runbook.md` 추가
- `terraform fmt -check -recursive` 통과
- `terraform validate` 통과

주의:

- 원본 root-owned 모듈 백업이 로컬에 남아 있다.
- 위치: `terraform/modules/.ubuntu-vm.root-owned`
- git에는 `.git/info/exclude`로 local exclude 처리됨.
- 완전 삭제하려면 수동 실행:

```bash
sudo rm -rf /home/sysadmin/homelab-infra/terraform/modules/.ubuntu-vm.root-owned
rm -rf /tmp/homelab-terraform-ubuntu-vm-root-owned-backup
```

## 현재 검증된 상태

마지막 확인 기준:

```text
terraform fmt -check -recursive: pass
terraform validate: pass
ansible playbook syntax: pass for site.yml and playbooks/*.yml
all servers failed systemd units: none
Wazuh agents: active
AD replication: [ALL GOOD]
Nextcloud cron: active
Nextcloud Talk: enabled
Nextcloud Mail: enabled
Identity flow verify: pass
```

## 핵심 문서

다음 세션에서 먼저 읽을 문서:

1. `docs/initial-build-guide.md`
2. `docs/ansible-playbook-catalog.md`
3. `docs/terraform-runbook.md`
4. `docs/identity-flow.md`
5. `docs/wazuh-siem.md`
6. `docs/nextcloud-mail.md`
7. `docs/iac-runbook.md`

## 다음 프로세스 제안

다음 세션에서는 아래 순서가 적절하다.

### 1. GitHub push 이후 remote 기준 확인

```bash
git status --short --branch
git log --oneline -10
```

### 2. 전체 smoke test runbook 만들기

현재는 개별 검증 playbook은 잘 정리되어 있다. 다음은 한 번에 전체 상태를 확인하는 `playbooks/verify-all.yml` 또는 `docs/verification-runbook.md`를 만드는 것이 좋다.

포함할 검증:

- all ping
- failed systemd unit
- AD replication/FSMO
- NTP
- Nextcloud status/cron/apps
- Keycloak realm/client/LDAP
- Mail services/ports
- Wazuh agent status
- Terraform fmt/validate

### 3. Wazuh hardening/AI-defense 준비

Wazuh 로그 수집은 붙었다. 다음은 경보 품질을 높이는 단계다.

후보 작업:

- Wazuh custom rule/local decoder 설계
- Nextcloud login/share/download 이벤트 탐지
- Keycloak LOGIN_ERROR 이벤트 룰링
- Mail brute force / auth failure 룰링
- AD password/account lockout 이벤트 룰링
- alert 요약용 AI pipeline 설계 문서 작성

### 4. Keycloak 운영 hardening

현재 Keycloak은 `start-dev` 기반 systemd로 보인다. 운영 기준으로는 추후 hardening 필요.

후보 작업:

- reverse proxy/TLS 정리
- production mode 전환 검토
- admin password/Vault 관리 정리
- SAML legacy 완전 제거 여부 결정

### 5. Nextcloud Talk TURN/HPB 검토

현재 Talk는 enabled 상태다. 내부 메시징은 가능하지만 영상회의/외부 접속 안정성을 위해 다음이 필요할 수 있다.

- coturn 서버 또는 role 추가
- TURN secret Vault화
- Talk High Performance Backend 검토

## 다음 세션 시작 프롬프트 예시

```text
지난 세션 handoff는 docs/session-handoff-2026-07-04.md에 있어.
현재 sme-security-infra는 Terraform fmt/validate 통과, Ansible playbooks syntax 통과, AD→Keycloak→Nextcloud identity flow 검증, Wazuh agent/log 표준화, Nextcloud Talk/Mail 활성화까지 완료된 상태야.
다음 단계로 전체 smoke test/verification runbook을 만들고, 이후 Wazuh hardening과 AI-defense pipeline 설계를 진행하자.
```
