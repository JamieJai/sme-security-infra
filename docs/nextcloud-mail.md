# Nextcloud Mail Integration

Nextcloud는 사내 포털 역할을 맡고, `mail01`은 실제 메일 backend 역할을 맡는다. Nextcloud Mail 앱은 사용자가 웹에서 IMAP/SMTP 계정을 연결해 사용할 수 있게 한다.

## 구성 흐름

```text
Samba AD user mail attribute
  → Postfix virtual mailbox map
  → Dovecot IMAP/LDAPS auth
  → Nextcloud Mail app
```

## 적용 순서

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook playbooks/mail-server.yml --vault-password-file .vault_pass
ansible-playbook playbooks/dovecot-conf.yml --vault-password-file .vault_pass
ansible-playbook playbooks/mail-autoconfig.yml
ansible-playbook playbooks/nextcloud-mail.yml
```

## 역할 분리

- `mail01`: Postfix, Dovecot, TLS, Maildir, autoconfig 제공
- `nextcloud`: Mail 앱, 시스템 알림 SMTP, 사용자 웹메일 UI
- `dc02/dc01`: AD 사용자, mail 속성, LDAP 인증 source

## 사용자 계정 자동 등록을 하지 않는 이유

Nextcloud Mail 앱의 사용자별 IMAP 계정 등록에는 사용자 메일 비밀번호가 필요하다. 비밀번호를 Ansible이나 Vault에 수집하는 구조는 보안상 좋지 않다. 따라서 IaC는 앱과 서버 연결성만 보장하고, 사용자별 Mail 앱 계정은 autoconfig를 통해 사용자가 직접 추가하는 기준으로 둔다.

## 검증 명령

```bash
ansible mail_server -b -m command -a 'systemctl is-active postfix dovecot mail-autoconfig-http'
ansible mail_server -b -m command -a 'ss -ltnp'
ansible nextcloud_server -b -m command -a 'sudo -u www-data php /var/www/nextcloud/occ config:system:get mail_smtphost'
ansible nextcloud_server -b -m shell -a 'sudo -u www-data php /var/www/nextcloud/occ app:list --output=json | php -r '''$j=json_decode(stream_get_contents(STDIN), true); echo isset($j["enabled"]["mail"]) ? "mail enabled\n" : "mail missing\n";''''
```

정상 기준:

- `postfix`, `dovecot`, `mail-autoconfig-http` active
- `mail01`에서 25, 587, 993 listen
- Nextcloud Mail 앱 enabled
- Nextcloud에서 `mail01.toss.lan:25`, `:587`, `:993` 접근 가능
