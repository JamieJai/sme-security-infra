# Legacy Ansible Playbooks

이 디렉터리는 현재 운영 기준에서 제외된 과거 playbook을 보관한다.

## 보관 기준

- `keycloak-sso-setup.yml`: 초기 SAML 중심 Keycloak/Nextcloud/Wazuh client 구성이다. 현재 Nextcloud 기준은 OIDC이며, 운영 runbook은 `playbooks/nextcloud-oidc-sso.yml`, `playbooks/nextcloud-oidc-groups.yml`, `playbooks/identity-flow-verify.yml`을 사용한다.
- `keycloak-deploy.yml`: 초기 Keycloak 설치용 단일 playbook이다. 운영 중인 Keycloak 서버에 재실행하면 systemd unit과 admin password를 덮을 수 있으므로 현재 초기 구축 runbook에서 제외한다.
- `mail-server.yml`: 루트 경로의 과거 mail 통합 playbook이다. 현재 mail 기준은 `playbooks/mail-server.yml`, `playbooks/dovecot-conf.yml`, `playbooks/mail-autoconfig.yml`, `playbooks/nextcloud-mail.yml`이다.

이 파일들은 참조 목적으로만 남긴다. 운영 적용 전에는 현재 role/playbook 구조에 맞게 재검토해야 한다.
