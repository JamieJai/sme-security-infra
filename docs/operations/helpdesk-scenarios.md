# Helpdesk Scenarios Runbook

이 문서는 IT Manager 관점에서 반복적으로 발생할 수 있는 사용자 문의를 read-only 진단 workflow로 정리한다. 목표는 증상을 듣고 바로 복구 명령을 실행하는 것이 아니라, 영향 범위와 원인을 먼저 좁히고 운영 증적을 남긴 뒤 필요한 변경만 승인받아 수행하는 것이다.

## 운영 원칙

- 먼저 사용자의 증상, 발생 시각, 대상 계정, 대상 PC, 사용 네트워크를 확인한다.
- 첫 진단은 read-only 명령과 기존 verification playbook으로 수행한다.
- 비밀번호, OTP, ODJ blob, raw token, webhook URL, vault 값은 티켓/Notion/Slack에 기록하지 않는다.
- 계정 disable/delete, AD computer object cleanup, service restart, firewall 변경, Terraform apply 같은 운영 변경은 별도 승인 후 실행한다.
- 결과는 Markdown artifact 또는 SQLite operations DB에 남기고, 재발 가능성이 있으면 runbook이나 automation task로 전환한다.
- PC 관련 문의는 먼저 `scripts/register-endpoint.sh`로 등록된 endpoint asset record가 있는지 확인한다.
- ticket event와 운영 지표는
  `docs/operations/helpdesk-metrics-runbook.md` 기준으로 기록하고 모의 문의는
  `simulation`으로 분류한다.

## 공통 접수 템플릿

사용자에게 먼저 확인할 항목:

| 항목 | 예시 | 목적 |
|---|---|---|
| 사용자 ID | `kim.chulsoo` | AD/Keycloak/Nextcloud/Mail 기준 계정 확인 |
| PC 이름 | `PC-2026071001` | AD computer object와 ODJ package 매칭 |
| 발생 시각 | `2026-07-10 09:20 KST` | Wazuh, auth log, mail log 조회 기준 |
| 네트워크 | 사내망, VPN, 외부망 | AD DNS/DC 접근 가능성 판단 |
| 오류 메시지 | screenshot 또는 문구 | 사용자 입력 오류와 시스템 오류 구분 |
| 최근 변경 | 신규 입사, 부서 이동, PC 교체 | 계정/그룹/장비 lifecycle 연결 |

공통 기록 형식:

```text
symptom:
impact:
initial_scope:
read_only_checks:
likely_cause:
temporary_action:
permanent_action:
evidence:
follow_up:
```

## 진단 스크립트

공통 진단 리포트는 `scripts/helpdesk-diagnose.sh`로 생성한다. 기본 실행은 서버에 접속하지 않고 scenario별 확인 항목과 read-only 명령 목록만 Markdown으로 남긴다. 실제 read-only Ansible 확인까지 수행하려면 `--execute`를 명시한다.

```bash
./scripts/helpdesk-diagnose.sh \
  --scenario domain-join \
  --username kim.chulsoo \
  --computer-name PC-2026071001 \
  --symptom "ODJ package 실행 후 도메인 로그인 실패"

./scripts/helpdesk-diagnose.sh \
  --scenario nextcloud-folder \
  --username kim.chulsoo \
  --symptom "Finance 폴더가 보이지 않음" \
  --execute
```

지원 scenario:

- `domain-join`
- `ad-login`
- `windows-gpo`
- `sso`
- `nextcloud-folder`
- `mail-login`
- `it-health`

생성 결과는 `artifacts/helpdesk/`와 `.codex/mcp/homelab_ops.sqlite`에 기록된다.
PC 이름이나 username이 입력되면 `.codex/mcp/homelab_ops.sqlite`의 endpoint asset record를 조회해 owner, employee ID, package path, asset tag 같은 context를 report에 포함한다.

티켓 접수, 최초 응답, 해결, 재오픈과 기간별 KPI는 각각
`scripts/helpdesk-ticket.py`, `scripts/helpdesk-metrics.py`로 기록한다. 진단
리포트의 `TBD` 항목은 자동 추측값이 아니라 담당자가 read-only 결과를 검토한 뒤
티켓 resolution에 확정할 내용이다.

## Scenario 1. Windows PC 도메인 가입 실패

### 증상

- `run-as-admin.cmd` 실행 후 도메인 가입이 실패한다.
- `toss.lan`을 찾을 수 없다는 오류가 나온다.
- ODJ package 적용 후 재부팅했지만 도메인 로그인 화면이 기대대로 보이지 않는다.

### 우선 판단

PC 도메인 가입 실패는 크게 세 가지로 나눈다.

1. DNS가 AD DNS를 보지 않는 경우
2. PC 이름과 ODJ blob 또는 AD computer object가 맞지 않는 경우
3. join 권한 또는 ODJ package 자체가 잘못 발급된 경우

### Read-only 진단

사용자 PC에서 확인할 항목:

```powershell
hostname
Get-DnsClientServerAddress
Resolve-DnsName toss.lan
Resolve-DnsName dc02.toss.lan
Get-CimInstance Win32_ComputerSystem | Select-Object Name,Domain,PartOfDomain
```

컨트롤 노드에서 AD object 확인:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool computer show PC-2026071001"
```

ODJ package 기준 확인:

- package directory가 사용자/장비별로 맞는지 확인한다.
- `odj.blob`을 다른 PC에서 재사용하지 않았는지 확인한다.
- ODJ package에 기록된 `Computer Name`과 실제 hostname이 일치하는지 확인한다.

### 조치 기준

- DNS 문제면 AD DNS `192.168.0.21`, `192.168.0.20`을 먼저 적용하고 재시도한다.
- hostname이 다르면 ODJ blob을 재사용하지 않고 새 computer name 기준으로 재발급한다.
- 잘못 배포된 package는 배포 경로에서 제거하고 AD computer object disable 여부를 사용자 승인 후 결정한다.

## Scenario 2. 도메인 가입 후 AD 로그인 실패

### 증상

- PC는 도메인에 가입된 것처럼 보이지만 AD 계정으로 로그인할 수 없다.
- `The trust relationship failed` 또는 인증 서버를 찾을 수 없다는 메시지가 나온다.
- 사내망에서는 되지만 외부망 또는 특정 Wi-Fi에서는 실패한다.

### 우선 판단

도메인 가입과 AD 로그인은 별개의 단계다. ODJ는 오프라인 상태에서도 가입 요청을 적용할 수 있지만, 실제 AD 사용자 로그인에는 AD DNS/DC 접근이 필요하다.

### Read-only 진단

사용자 PC:

```powershell
Get-CimInstance Win32_ComputerSystem | Select-Object Name,Domain,PartOfDomain
nltest /dsgetdc:toss.lan
klist
whoami /fqdn
```

AD 쪽 computer object:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool computer show PC-2026071001"
```

사용자 계정 상태:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool user show kim.chulsoo"
```

### 조치 기준

- AD DNS/DC discovery가 실패하면 네트워크/VPN/DNS를 먼저 보정한다.
- 사용자 계정이 disabled 또는 password expired 상태면 계정 lifecycle runbook으로 넘긴다.
- trust relationship 문제는 PC 재가입 또는 computer object reset이 필요할 수 있으므로 운영 변경 승인 후 처리한다.


## Scenario 2-1. 도메인 로그인 후 GPO 또는 공유 드라이브 미적용

### 증상

- AD 계정 로그인은 되지만 바탕화면 정책이 보이지 않는다.
- `Z:` 같은 네트워크 드라이브가 자동 매핑되지 않는다.
- `gpresult`에는 사용자 GPO가 보이지만 실제 사용자 환경이 기대와 다르다.

### 우선 판단

도메인 가입, AD 로그인, user GPO 적용, SMB 인증은 서로 다른 단계다. `PartOfDomain=True`와 로그인 성공만으로 drive mapping 또는 wallpaper 적용까지 보장되지는 않는다.

### Read-only 진단

사용자 PC의 실제 로그인 세션에서 확인:

```cmd
whoami
gpresult /r
net use
reg query "HKCU\Control Panel\Desktop" /v WallPaper
```

GPO 처리 오류 확인:

```cmd
wevtutil qe Application /q:"*[System[(EventID=4098)]]" /c:20 /rd:true /f:text
```

storage01 SMB/domain member 상태 확인:

```bash
ansible storage_server -i ansible/inventory/hosts -b -m command -a "testparm -s"
ansible storage_server -i ansible/inventory/hosts -b -m shell -a "wbinfo -r kim.chulsoo"
ansible storage_server -i ansible/inventory/hosts -b -m shell -a "wbinfo --group-info 'TOSS\\Domain Users'"
```

SMB SPN 확인:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool spn list STORAGE01$"
```

### 조치 기준

- wallpaper 값이 사용자별 로컬 경로면 `ansible/playbooks/gpo-wallpaper-policy.yml`로 공용 읽기 가능 UNC 경로로 바꾼다.
- `testparm`에 idmap range 오류가 있거나 `wbinfo`가 도메인 그룹을 못 풀면 storage01 Samba idmap 설정을 먼저 보정한다.
- `gpupdate`가 `\\toss.lan\SysVol`의 `gpt.ini` 접근 실패를 보고하면 클라이언트가 선택한 DC의 SYSVOL ACL을 확인하고 `samba-tool ntacl sysvolreset`을 검토한다.
- `STORAGE01$`에 `CIFS/storage01`와 `CIFS/storage01.toss.lan` SPN이 없으면 `ansible/playbooks/storage-smb-spn.yml`로 추가한다.
- GPO 수정, Samba 재시작, AD SPN 추가는 운영 변경이므로 승인 후 수행한다.

## Scenario 3. Keycloak SSO 로그인 실패

### 증상

- AD 계정은 맞지만 SSO 로그인에 실패한다.
- Nextcloud OIDC 로그인 화면에서 인증 후 돌아오지 못한다.
- 특정 사용자만 실패하고 다른 사용자는 정상이다.

### 우선 판단

SSO 실패는 AD 계정 문제, Keycloak LDAP federation 문제, OIDC client 설정 문제로 나눠 본다.

### Read-only 진단

대상 사용자 AD 확인:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool user show kim.chulsoo"
```

전체 identity baseline 확인:

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags identity,keycloak --vault-password-file .vault_pass
```

Keycloak 서비스 상태 확인:

```bash
ansible keycloak -i ansible/inventory/hosts -b -m command -a "systemctl is-active keycloak"
```

### 조치 기준

- 단일 사용자만 실패하면 AD 사용자 속성, 그룹, mail/displayName 누락 여부를 먼저 본다.
- 전체 사용자가 실패하면 Keycloak service, LDAP federation, HAProxy/LDAPS 경로를 본다.
- OIDC redirect/client secret 변경은 운영 영향이 있으므로 승인 후 수행한다.

## Scenario 4. Nextcloud 부서 폴더가 보이지 않음

### 증상

- 로그인은 되지만 `/HR`, `/Finance`, `/IT`, `/Security` 같은 부서 폴더가 보이지 않는다.
- 같은 부서의 다른 사용자는 정상이다.
- 부서 이동 후 이전 폴더만 보이거나 새 폴더가 보이지 않는다.

### 우선 판단

Nextcloud 부서 폴더 문제는 AD group, Keycloak groups claim, Nextcloud group provisioning, external storage 제한 중 하나에서 끊긴 것이다.

### Read-only 진단

AD group membership 확인:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool user show kim.chulsoo"
```

Identity/Nextcloud baseline 확인:

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags identity,nextcloud --vault-password-file .vault_pass
```

사용자에게 확인할 항목:

- 최근 부서 이동 여부
- 로그아웃 후 재로그인 여부
- 브라우저 캐시 또는 다른 브라우저에서도 동일한지 여부

### 조치 기준

- AD group이 틀리면 온보딩/부서 이동 workflow로 수정한다.
- AD group은 맞지만 Nextcloud만 틀리면 Keycloak claim과 Nextcloud OIDC group provisioning을 확인한다.
- external storage 설정 변경은 다른 사용자에게 영향을 줄 수 있으므로 read-only 검증 후 승인받아 수정한다.

## Scenario 5. Mail 로그인 실패

### 증상

- Nextcloud Mail 또는 메일 클라이언트에서 IMAP/SMTP 로그인이 실패한다.
- SSO는 되지만 메일만 실패한다.
- 신규 입사자 계정에서 메일함이 없거나 인증 실패가 발생한다.

### 우선 판단

메일 로그인은 AD 계정, `mail` attribute, Postfix mailbox map, Dovecot LDAPS auth, Nextcloud Mail app 설정으로 나눠 본다.

### Read-only 진단

사용자 AD mail attribute 확인:

```bash
ansible active_dc -i ansible/inventory/hosts -b -m command -a "samba-tool user show kim.chulsoo"
```

Mail baseline 확인:

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags mail --vault-password-file .vault_pass
```

서비스 상태 확인:

```bash
ansible mail_server -i ansible/inventory/hosts -b -m command -a "systemctl is-active postfix"
ansible mail_server -i ansible/inventory/hosts -b -m command -a "systemctl is-active dovecot"
```

### 조치 기준

- `mail` attribute가 없으면 온보딩 workflow로 보정한다.
- 사용자 비밀번호는 IT팀이 수집하지 않는다. 사용자가 직접 입력하고, 로그에는 비밀번호를 남기지 않는다.
- mail map 재생성이나 Dovecot 설정 변경은 다른 사용자 영향이 있으므로 승인 후 수행한다.

## Scenario 6. 전체 IT health 검증 실패

### 증상

- `verify-and-report.sh` 또는 `verify-all.yml`이 실패한다.
- Slack에 failed/partial 상태가 전달된다.
- 특정 서비스 장애인지 전체 인프라 장애인지 불명확하다.

### 우선 판단

전체 검증 실패는 첫 실패 task를 기준으로 범위를 좁힌다. 전체 playbook을 반복 실행하기보다 해당 tag로 재현하는 것이 우선이다.

### Read-only 진단

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags ad --vault-password-file .vault_pass
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags keycloak,nextcloud --vault-password-file .vault_pass
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags mail --vault-password-file .vault_pass
ansible-playbook -i inventory/hosts playbooks/verify-all.yml --tags wazuh --vault-password-file .vault_pass
```

결과 artifact 확인:

```text
artifacts/verification/
reports/
.codex/mcp/homelab_ops.sqlite
```

### 조치 기준

- 단일 서비스 실패면 해당 service runbook으로 넘긴다.
- 여러 서비스가 동시에 실패하면 DNS, AD, network, storage 같은 공통 dependency를 먼저 본다.
- 복구 작업은 verification playbook에서 자동 호출하지 않는다.

## Incident Review 기록 기준

반복되거나 영향이 큰 helpdesk 사건은 아래 형식으로 Notion 또는 Markdown에 회고를 남긴다.

```text
Title:
Date/Time:
Affected users:
Affected services:
Timeline:
Root cause:
Detection:
Resolution:
What went well:
What to improve:
Follow-up automation:
```

## Definition of Done

Helpdesk scenario 처리 완료 기준:

- 사용자 증상과 발생 시각이 기록됐다.
- read-only 진단 결과가 남았다.
- 원인 또는 다음 확인 범위가 명확해졌다.
- 운영 변경이 필요하면 사용자 승인 후 실행했다.
- 결과가 Markdown, SQLite, Slack, Notion 중 적절한 채널에 기록됐다.
- 반복 가능성이 있으면 runbook 또는 automation backlog로 전환했다.
