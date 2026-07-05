# Identity Flow Runbook

이 문서는 `Samba AD → Keycloak → Nextcloud` 사용자/그룹/주소록 흐름을 검증하고 운영하는 기준이다.

## 목표 흐름

```text
Samba AD users/groups/mail/displayName
  → Keycloak Samba-AD LDAP federation
  → Keycloak nextcloud-oidc OIDC client
  → groups claim
  → Nextcloud user_oidc provider
  → Nextcloud group provisioning / storage ACL / addressbook
```

## 적용 순서

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook playbooks/nextcloud-oidc-sso.yml
ansible-playbook playbooks/nextcloud-oidc-groups.yml
ansible-playbook playbooks/nextcloud-ad-addressbook.yml
ansible-playbook playbooks/identity-flow-verify.yml
```

## 정상 기준

- Keycloak realm `homelab` enabled
- Keycloak LDAP federation `Samba-AD` 존재
- Keycloak OIDC client `nextcloud-oidc` enabled, confidential client
- OIDC protocol mapper `nextcloud-groups`가 `groups` claim을 ID/access/userinfo token에 포함
- Nextcloud OIDC provider `homelab-keycloak` 존재
- Nextcloud group provisioning enabled
- login restriction group whitelist enabled
- Nextcloud 그룹 존재:
  - `HR_Staff`
  - `Finance_Staff`
  - `IT_Admins`
  - `Security_Team`
- 부서별 external storage mount가 해당 그룹으로 제한
- system addressbook exposed

## 주소록 설계

Nextcloud 주소록은 DC의 SSSD가 아니라 AD의 `mail`, `displayName`, `sAMAccountName` 속성을 기준으로 동기화한다. DC는 Samba AD/DNS/Kerberos에 집중하고, 직원 정보 노출은 Nextcloud 주소록과 Keycloak claim 흐름으로 처리한다.

## 검증 명령

```bash
ansible-playbook playbooks/identity-flow-verify.yml
ansible nextcloud_server -b -m command -a 'sudo -u www-data php /var/www/nextcloud/occ user_oidc:providers --output=json_pretty'
ansible nextcloud_server -b -m command -a 'sudo -u www-data php /var/www/nextcloud/occ files_external:list --output=json_pretty'
```
