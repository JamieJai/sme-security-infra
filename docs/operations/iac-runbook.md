# IaC 운영 Runbook

이 runbook은 `sme-security-infra`를 재현 가능한 IaC 구조로 운영하기 위한 기준 실행 순서다. Terraform은 VM과 기본 인프라를 만들고, Ansible은 OS/서비스/보안 구성을 담당한다. Terraform 세부 운영 기준은 `docs/reference/terraform-runbook.md`를 따른다.

## 목표 아키텍처

| 계층 | 서버 | 책임 |
|---|---|---|
| Directory | `dc02`, `dc01` | Samba AD, DNS, Kerberos, LDAP, 장애 대응 |
| IAM | `keycloak` | AD LDAP federation, SSO/OIDC, 앱 인증 허브 |
| Collaboration | `nextcloud` | 사내 클라우드, 사용자 포털, 공유폴더 UI, Nextcloud Talk 메신저 |
| Storage | `storage01` | 부서별 공유 스토리지, Nextcloud external storage backend |
| Mail | `mail01` | Postfix/Dovecot, AD LDAP 메일 인증 |
| SIEM | `wazuh` | 로그/보안 이벤트 수집, 취약점/무결성 감시 |
| Automation | `automation01` | Terraform, Ansible, Git 운영 노드 |

## 기준 실행 순서

1. Terraform
   - VM, CPU, RAM, 디스크, 네트워크/IP를 생성한다.
   - `terraform.tfvars`와 state는 Git에 저장하지 않는다.

2. Bootstrap
   - SSH, sudo, hostname, timezone, DNS resolver, 기본 패키지를 맞춘다.
   - 모든 서버가 Ansible `ping`에 성공해야 다음 단계로 간다.

3. Samba AD
   - `dc02`를 active DC/FSMO 기준으로 둔다.
   - `dc01`은 additional DC로 유지해 장애 시 인증/DNS 업무가 계속되게 한다.
   - replication, FSMO, DNS, Kerberos, password/account policy를 검증한다.

4. Storage
   - `storage01:/data/shared`를 부서별 디렉터리 구조로 만든다.
   - AD 그룹 기준 권한 모델을 유지한다.
   - Kerberized NFS는 별도 hardening 단계에서 결정한다.

5. Keycloak
   - AD LDAP federation을 구성한다.
   - LDAPS HA endpoint를 통해 `dc02` 우선, 장애 시 `dc01` fallback을 사용한다.
   - Nextcloud 등 내부 앱 client와 group claim mapper를 코드로 관리한다.

6. Nextcloud
   - Apache/PHP/MariaDB를 구성한다.
   - Keycloak OIDC 로그인, AD 그룹 provisioning, external storage mount를 적용한다.
   - background job은 cron으로 실행한다. 사내 메신저는 Nextcloud Talk를 기본안으로 사용한다.

7. Mail
   - Postfix/Dovecot을 구성한다.
   - AD LDAP 인증과 Maildir 자동 보정을 적용한다.
   - Nextcloud SMTP/Mail 앱 연동 기준을 검증한다.

8. Wazuh
   - manager/indexer/dashboard를 구성한다.
   - 모든 서버에 agent를 배포하고 역할별 로그 수집을 적용한다.
   - AD, Keycloak, Nextcloud, Mail, SSH/sudo/auth 로그를 수집한다.

9. Verification
   - AD replication/FSMO
   - Keycloak LDAP federation과 OIDC login
   - Nextcloud login, group provisioning, storage mount, cron
   - Mail IMAP/SMTP
   - Wazuh agent enrollment와 alert 수집
   - Samba backup과 certificate expiry monitor timer

## 운영 원칙

- `active_dc` inventory 그룹은 AD 쓰기 작업의 단일 기준점이다.
- 임시 복구 playbook과 상시 운영 playbook을 분리한다.
- Vault password 없이는 secret이 필요한 playbook syntax/check가 실패할 수 있다.
- Nextcloud, Mail, Keycloak은 AD/Keycloak identity 흐름을 기준으로 연결한다.
- Wazuh는 AI 방어형 분석을 붙이기 전, 먼저 이벤트 수집 품질을 안정화한다.
