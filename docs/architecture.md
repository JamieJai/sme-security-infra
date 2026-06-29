# Homelab Infrastructure Architecture

## 1. 목적

이 인프라는 `toss.lan` 내부 도메인을 기준으로 AD 계정, Keycloak SSO, Nextcloud 파일 협업, mail/storage 연동, Wazuh 보안 모니터링을 구성한다. Terraform은 Proxmox VM 생성을 담당하고, Ansible은 OS/서비스/정책 구성을 담당한다.

## 2. 도메인 및 네트워크

| 항목 | 값 |
|---|---|
| AD Domain | `toss.lan` |
| Kerberos Realm | `TOSS.LAN` |
| DNS/NTP | `192.168.0.20` |
| Nextcloud URL | `https://192.168.0.50`, `https://nextcloud.toss.lan` |
| Keycloak Realm | `homelab` |

## 3. 서버 구성

| 서버 | IP | 역할 |
|---|---:|---|
| `dc01` | `192.168.0.20` | Samba AD DC, DNS, Chrony |
| `dc02` | `192.168.0.21` | Samba additional DC |
| `wazuh` | `192.168.0.30` | Wazuh manager/dashboard |
| `automation01` | `192.168.0.40` | Terraform/Ansible/Git 운영 노드 |
| `nextcloud` | `192.168.0.50` | Nextcloud, Apache/PHP, OIDC client |
| `keycloak` | `192.168.0.60` | Keycloak IAM, AD LDAP federation |
| `storage01` | `192.168.0.70` | NFS/SMB shared storage |
| `mail01` | `192.168.0.80` | Postfix/Dovecot, AD LDAP mail auth |

## 4. AD 구조와 그룹

표준 OU는 `IT`, `HR`, `Finance`, `Security`, `Users`, `Computers`를 사용한다. 주요 보안 그룹은 다음과 같다.

| 그룹 | 용도 |
|---|---|
| `HR_Staff` | HR 부서 파일 권한 및 Nextcloud 그룹 |
| `Finance_Staff` | Finance 부서 파일 권한 및 Nextcloud 그룹 |
| `IT_Admins` | IT 부서 파일 권한, legacy root storage 접근, 운영 권한 |
| `Security_Team` | Security 부서 파일 권한 및 Nextcloud 그룹 |
| `Server_Admins` | 서버 운영 권한 |

## 5. SSO 흐름

1. 사용자는 Nextcloud의 OIDC 로그인 버튼을 선택한다.
2. Nextcloud `user_oidc` provider `homelab-keycloak`가 Keycloak `homelab` realm으로 redirect한다.
3. Keycloak은 Samba AD LDAP federation `Samba-AD`를 통해 AD 사용자 인증을 수행한다.
4. Keycloak client `nextcloud-oidc`는 `nextcloud-groups` protocol mapper로 AD 그룹을 `groups` claim에 포함한다.
5. Nextcloud는 `groups` claim을 `mappingGroups=groups`로 읽고 group provisioning을 수행한다.

현재 Nextcloud OIDC provider 설정은 다음 정책을 사용한다.

| 설정 | 값 |
|---|---|
| UID mapping | `preferred_username` |
| Display name | `name` |
| Email | `email` |
| Groups claim | `groups` |
| Group provisioning | enabled |
| Group whitelist | `HR_Staff`, `Finance_Staff`, `IT_Admins`, `Security_Team` |
| Login restriction by whitelist | disabled |

## 6. Storage 권한 모델

`storage01:/data/shared`는 Nextcloud 서버에 `/mnt/storage01`로 연결된다. Nextcloud에는 부서별 local external storage mount를 별도로 만들고, 각 mount에 Nextcloud 그룹 제한을 건다.

| Nextcloud mount | Backend path | Nextcloud group |
|---|---|---|
| `/HR` | `/mnt/storage01/departments/hr` | `HR_Staff` |
| `/Finance` | `/mnt/storage01/departments/finance` | `Finance_Staff` |
| `/IT` | `/mnt/storage01/departments/it` | `IT_Admins` |
| `/Security` | `/mnt/storage01/departments/security` | `Security_Team` |
| `/nfs_storage` | `/mnt/storage01` | `IT_Admins` only |

이 권한 모델의 기준은 Nextcloud group provisioning이다. AD 그룹 변경 후 사용자가 OIDC로 다시 로그인하면 Nextcloud 사용자 그룹이 갱신되고, 그 그룹에 맞는 mount만 보인다.

## 7. Mail 연동

`mail01`은 Postfix/Dovecot 기반이며 LDAP 설정은 `ldaps://192.168.0.20:636`을 기준으로 한다. Nextcloud는 `mail.toss.lan` SMTP 설정으로 내부 알림 메일을 보낸다.

## 8. TLS 인증서

현재 Nextcloud HTTPS는 self-signed 인증서로 부트스트랩되어 있다. 내부 CA 또는 정식 인증서로 교체할 때는 다음 환경 변수를 지정하고 playbook을 실행한다.

```bash
NEXTCLOUD_TLS_CERT_SRC=/path/to/nextcloud.crt NEXTCLOUD_TLS_KEY_SRC=/path/to/nextcloud.key NEXTCLOUD_TLS_CHAIN_SRC=/path/to/chain.crt ansible-playbook playbooks/nextcloud-tls.yml
```

`NEXTCLOUD_TLS_CHAIN_SRC`는 체인 파일이 있을 때만 지정한다. private key는 repo에 저장하지 않는다.

## 9. Secret 관리

- `terraform/terraform.tfvars`는 `.gitignore` 대상이며 실제 secret은 로컬 전용으로만 둔다.
- 공유용 샘플은 `terraform/terraform.tfvars.example`을 사용한다.
- Ansible 운영 secret은 `ansible/group_vars/vault.yml` 또는 별도 Vault 파일에 넣는다.
- Keycloak 임시 playbook은 hardcoded admin password 대신 Keycloak systemd unit의 `KEYCLOAK_ADMIN_PASSWORD`를 읽는다.
- 남은 root-owned `ansible/host_vars/dc01.yml`, `ansible/host_vars/dc02.yml`의 평문 AD secret은 권한 조정 후 Vault 변수로 이동해야 한다.

## 10. 운영 명령

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook playbooks/nextcloud-oidc-sso.yml
ansible-playbook playbooks/nextcloud-oidc-groups.yml
ansible-playbook playbooks/nextcloud-integrations.yml
```

브라우저 검증은 `https://192.168.0.50` 접속 후 OIDC 로그인 버튼을 누르고 AD 계정으로 로그인한다. 로그인 후 `occ user:list`, `occ group:list`, `occ files_external:list --output=json_pretty`로 생성 사용자, 그룹, storage mount를 확인한다.
