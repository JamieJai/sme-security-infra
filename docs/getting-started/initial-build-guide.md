# 초기 구축 가이드

이 문서는 빈 VM 환경에서 `sme-security-infra`를 다시 구성할 때의 기준 실행 순서를 정의한다. 모든 명령은 기본적으로 `/home/sysadmin/homelab-infra/ansible`에서 실행한다.

## 0. 기본 원칙

Playbook 분류와 위험도는 `docs/reference/ansible-playbook-catalog.md`와 `docs/operations/operation-modes.md`를 함께 확인한다.

- Terraform은 VM과 인프라 자원을 만든다.
- Ansible은 OS, 인증, 서비스, 보안 정책을 구성한다.
- 운영 기준 playbook은 `ansible/playbooks/` 아래에 둔다.
- 루트 `ansible/*.yml`은 신규 운영 기준으로 사용하지 않는다.
- secret이 필요한 playbook은 `--vault-password-file .vault_pass`를 사용한다.
- DC 재구축/복구 playbook은 기존 운영 DC를 손상시킬 수 있으므로 runbook 목적 없이 실행하지 않는다.

## 1. Terraform VM 구성

세부 운영 기준은 `docs/reference/terraform-runbook.md`를 확인한다.

```bash
cd /home/sysadmin/homelab-infra/terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Terraform 완료 후 inventory의 IP와 실제 VM IP가 맞는지 확인한다.

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible all -m ping
```

## 2. 공통 OS 기준 구성

```bash
ansible-playbook playbooks/common.yml
```

확인:

```bash
ansible all -m command -a 'hostnamectl'
ansible all -b -m command -a 'timedatectl show -p Timezone -p NTPSynchronized --value'
```

## 3. Samba AD/DC 구성

기준 정책:

- `dc02`는 active DC/FSMO 기준점이다.
- `dc01`은 장애 대응용 additional DC다.
- `active_dc` inventory 그룹은 AD 쓰기 작업의 단일 대상이다.
- DC에서는 SSSD를 사용하지 않는다. 일반 Linux member server에서만 SSSD/AD join을 사용한다.

운영 보정/정책 적용:

```bash
ansible-playbook playbooks/ad-dc-chrony.yml
ansible-playbook playbooks/ad-dc-disable-sssd.yml
ansible-playbook playbooks/ad-dc-firewall.yml
ansible-playbook playbooks/account-lockout.yml
ansible-playbook playbooks/password-policy.yml
```

검증:

```bash
ansible primary_dc:secondary_dc -b -m command -a 'samba-tool drs showrepl --summary'
ansible primary_dc:secondary_dc -b -m command -a 'samba-tool fsmo show'
ansible primary_dc:secondary_dc -b -m command -a 'chronyc tracking'
```

주의: `playbooks/rebuild-dc01.yml`, `playbooks/additional-dc.yml`, `playbooks/ad-server.yml`은 DC 복구/재조정 목적이다. 초기 구축과 장애 복구 상황을 구분해서 실행한다.

## 4. Storage 구성

```bash
ansible-playbook playbooks/storage-policy.yml
ansible-playbook playbooks/storage-rpc-gssd.yml
```

현재 기준은 일반 NFS/SMB를 먼저 완성하는 것이다. Kerberized NFS는 hardening 단계에서 별도 keytab/SPN 설계를 한 뒤 활성화한다.

검증:

```bash
ansible storage_server -b -m command -a 'systemctl is-active nfs-server smbd'
ansible storage_server -b -m command -a 'systemctl --failed --no-legend --no-pager'
```

## 5. Keycloak IAM 구성

```bash
ansible-playbook playbooks/keycloak-ldap-ha.yml --vault-password-file .vault_pass
ansible-playbook playbooks/keycloak-ldap-ldaps.yml --vault-password-file .vault_pass
# Nextcloud OIDC client/provider is configured in the Nextcloud section with playbooks/nextcloud-oidc-sso.yml
```

목표 흐름:

```text
Samba AD → Keycloak LDAP federation → OIDC clients → Nextcloud/Wazuh/기타 앱
```

## 6. Nextcloud 클라우드/협업 구성

주의: `playbooks/nextcloud-server.yml`은 기본 설치 role을 포함하며 기존 `/var/www/nextcloud`를 제거하는 task가 있다. 운영 중인 서버에는 보정 전용 playbook을 우선 사용한다.

운영 보정/통합 적용:

```bash
ansible-playbook playbooks/nextcloud-cron.yml
ansible-playbook playbooks/nextcloud-oidc-sso.yml --vault-password-file .vault_pass
ansible-playbook playbooks/nextcloud-oidc-groups.yml
ansible-playbook playbooks/nextcloud-integrations.yml
ansible-playbook playbooks/nextcloud-mail.yml
ansible-playbook playbooks/nextcloud-ad-addressbook.yml
ansible-playbook playbooks/nextcloud-ad-addressbook-schedule.yml
ansible-playbook playbooks/identity-flow-verify.yml
ansible-playbook playbooks/nextcloud-talk.yml
```

검증:

```bash
ansible nextcloud_server -b -m command -a 'sudo -u www-data php /var/www/nextcloud/occ status'
ansible nextcloud_server -b -m command -a 'sudo -u www-data php /var/www/nextcloud/occ config:app:get core backgroundjobs_mode'
ansible nextcloud_server -b -m command -a 'crontab -u www-data -l'
```

## 7. Mail 구성

```bash
ansible-playbook playbooks/mail-server.yml --vault-password-file .vault_pass
ansible-playbook playbooks/dovecot-conf.yml --vault-password-file .vault_pass
ansible-playbook playbooks/mail-autoconfig.yml
```

검증:

```bash
ansible mail_server -b -m command -a 'systemctl is-active postfix dovecot'
```

Nextcloud는 `mail01`을 SMTP/IMAP backend로 사용한다. `playbooks/nextcloud-mail.yml`은 Nextcloud Mail 앱을 활성화하고, Nextcloud 서버에서 `mail01`의 SMTP/IMAP 포트 접근을 검증한다. 사용자별 Mail 앱 계정 등록은 사용자 비밀번호가 필요하므로 자동 생성하지 않고, mail autoconfig와 AD mail 속성을 기준으로 사용자가 연결한다.

## 8. Wazuh SIEM 구성

```bash
ansible-playbook playbooks/wazuh-server.yml
ansible-playbook playbooks/wazuh-agent-deploy.yml
ansible-playbook playbooks/wazuh-agent-logs.yml
```

목표 수집 대상:

- DC 인증/DNS/Kerberos 이벤트
- Keycloak 로그인/LDAP federation 이벤트
- Nextcloud/Apache/PHP 이벤트
- Mail Postfix/Dovecot 이벤트
- SSH/sudo/auth 로그
- 파일 무결성/FIM

## 9. 백업/모니터링 구성

```bash
ansible-playbook playbooks/samba-domain-backup.yml
ansible-playbook playbooks/certificate-expiry-monitor.yml
```

검증:

```bash
ansible active_dc -b -m command -a 'systemctl list-timers samba-domain-backup.timer --no-pager'
ansible primary_dc:secondary_dc:iam_server -b -m command -a 'systemctl list-timers certificate-expiry-monitor.timer --no-pager'
```

## 10. 최종 상태 점검

```bash
ansible all -m ping
ansible all -b -m command -a 'systemctl --failed --no-legend --no-pager'
ansible all -b -m command -a 'df -h /'
ansible all -b -m command -a 'timedatectl show -p Timezone -p NTPSynchronized --value'
```

정상 기준:

- 모든 서버 Ansible ping 성공
- DC replication `[ALL GOOD]`
- Nextcloud cron active 및 background mode `cron`
- Keycloak, Nextcloud, Mail, Wazuh 핵심 서비스 active
- 의도하지 않은 failed unit 없음

## 자동화 entrypoint

새 환경에서 전체 적용을 시도하기 전 `docs/getting-started/secrets-checklist.md`를 기준으로 secret material을 준비한다. 비파괴 검증은 `./scripts/full-check.sh`, 실제 적용은 `./scripts/full-apply.sh`를 사용한다.
