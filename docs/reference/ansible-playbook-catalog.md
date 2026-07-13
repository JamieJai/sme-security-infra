# Ansible Playbook 카탈로그

이 문서는 `ansible/playbooks/`의 playbook을 운영 목적별로 분류한다. 초기 구축 순서는 `docs/getting-started/initial-build-guide.md`를 기준으로 한다.

## 1. 초기 구축/운영 기준 playbook

| 단계 | Playbook | 목적 |
|---|---|---|
| Common | `playbooks/common.yml` | 공통 OS/hosts/DNS 기준 |
| AD | `playbooks/ad-dc-chrony.yml` | DC 시간 동기화 정책 |
| AD | `playbooks/ad-dns-records.yml` | Core `toss.lan` A/PTR/CNAME 레코드를 Samba AD DNS에 보정 |
| AD | `playbooks/ad-dc-disable-sssd.yml` | DC에서 SSSD 비활성화 |
| AD | `playbooks/ad-dc-firewall.yml` | DC 방화벽 |
| AD | `playbooks/ad-dns-forwarder.yml` | Samba AD DNS 외부 forwarder 보정 |
| AD | `playbooks/account-lockout.yml` | 계정 잠금 정책 |
| AD | `playbooks/password-policy.yml` | 암호 정책 |
| Storage | `playbooks/storage-policy.yml` | 부서별 공유 스토리지 정책 |
| Storage | `playbooks/storage-rpc-gssd.yml` | 일반 NFS 기준 rpc-svcgssd 비활성화 |
| Keycloak | `playbooks/keycloak-ldap-ha.yml` | Keycloak LDAP HA endpoint |
| Keycloak | `playbooks/keycloak-ldap-ldaps.yml` | LDAPS federation 보강 |
| Nextcloud | `playbooks/nextcloud-cron.yml` | Nextcloud background job cron |
| Nextcloud | `playbooks/nextcloud-oidc-sso.yml` | Keycloak OIDC client/provider |
| Nextcloud | `playbooks/nextcloud-oidc-groups.yml` | OIDC groups claim, group provisioning, storage ACL |
| Nextcloud | `playbooks/nextcloud-integrations.yml` | Nextcloud 기본 통합/SMTP |
| Nextcloud | `playbooks/nextcloud-mail.yml` | Nextcloud Mail 앱과 mail01 접근 검증 |
| Nextcloud | `playbooks/nextcloud-ad-addressbook.yml` | AD 사용자 주소록 동기화 |
| Nextcloud | `playbooks/nextcloud-ad-addressbook-schedule.yml` | 주소록 동기화 스케줄 |
| Nextcloud | `playbooks/identity-flow-verify.yml` | AD → Keycloak → Nextcloud 검증 |
| Nextcloud | `playbooks/nextcloud-talk.yml` | Nextcloud Talk 메신저 |
| Mail | `playbooks/mail-server.yml` | 기본 mail 도구 설치 |
| Mail | `playbooks/dovecot-conf.yml` | Dovecot LDAP/TLS 구성 |
| Mail | `playbooks/mail-autoconfig.yml` | Postfix/Dovecot/TLS/autoconfig/mailbox map |
| Wazuh | `playbooks/wazuh-server.yml` | Wazuh all-in-one 서버 |
| Wazuh | `playbooks/wazuh-apt-repository.yml` | Wazuh apt repository signed-by keyring 관리 |
| Wazuh | `playbooks/wazuh-agent-deploy.yml` | Wazuh agent 배포 |
| Wazuh | `playbooks/wazuh-agent-logs.yml` | 역할별 로그 수집 |
| Wazuh | `playbooks/wazuh-agent-windows.yml` | Windows endpoint Wazuh agent 설치 및 서비스 검증 |
| Wazuh | `playbooks/wazuh-custom-detections.yml` | Custom decoder/rule 배포 및 fixture test |
| Wazuh | `playbooks/wazuh-platform-hardening.yml` | Version hold, API bind, UFW, TLS 기준 적용 |
| Wazuh | `playbooks/wazuh-index-lifecycle.yml` | 30일 retention, 일일 snapshot 및 90일 정리 |
| Wazuh | `playbooks/wazuh-snapshot-replica.yml` | storage01 외부 snapshot 복제 및 가독성 검증 |
| Wazuh | `playbooks/wazuh-restore-test.yml` | 격리 indexer 월간 snapshot restore 검증 |
| Wazuh | `playbooks/wazuh-dashboard-certificate.yml` | Dashboard SAN 인증서, CA trust, rollback |
| Wazuh | `playbooks/wazuh-rbac.yml` | SSO RBAC, admin rotation, break-glass |
| Wazuh | `playbooks/wazuh-ai-shadow.yml` | read-only AI shadow collector 및 spool |
| Monitoring | `playbooks/grafana-apt-repository.yml` | Grafana apt repository signed-by keyring 관리 |
| Monitoring | `playbooks/samba-domain-backup.yml` | Active DC 백업 |
| Monitoring | `playbooks/certificate-expiry-monitor.yml` | 인증서 만료 모니터링 |
| Verification | `playbooks/verify-all.yml` | 전체 인프라 read-only smoke test |

## 2. 운영 작업 playbook

| Playbook | 목적 |
|---|---|
| `playbooks/ad-onboard-user.yml` | AD 사용자 온보딩 |
| `playbooks/ad-join-all.yml` | Linux member server AD join |
| `playbooks/ad-postconfig.yml` | AD 후속 구성 |
| `playbooks/endpoint-app-deployment-scope.yml` | Endpoint 표준 앱 배포 pilot 보안 그룹과 computer membership 준비 |
| `playbooks/endpoint-app-bootstrap-task.yml` | Pilot Windows endpoint에 SYSTEM startup task로 표준 앱 bootstrap 배포 |
| `playbooks/endpoint-onboarding.yml` | Windows endpoint onboarding 후 Wazuh security visibility 적용 |
| `playbooks/rotate-ad-administrator.yml` | AD Administrator 암호 회전 |
| `playbooks/nextcloud-tls.yml` | Nextcloud TLS 인증서 교체 |

## 3. 복구/위험 playbook

아래 playbook은 재구축/복구 상황에서만 사용한다. 운영 중인 서버에 무심코 실행하지 않는다.

| Playbook | 위험/주의점 |
|---|---|
| `playbooks/nextcloud-server.yml` | 기존 `/var/www/nextcloud` 제거 task가 있으므로 운영 서버에 직접 실행 금지 |
| `playbooks/rebuild-dc01.yml` | DC 재구축 목적. `rebuild_dc_confirm=true`와 사전 정리 필요 |
| `playbooks/additional-dc.yml` | DC join/reconcile 목적. bootstrap 대상 확인 필요 |
| `playbooks/ad-server.yml` | dc01 additional DC reconcile 용도. 일반 초기 구축 흐름에서는 직접 실행하지 않음 |
| `playbooks/repair-nextcloud-config.yml` | Nextcloud config.php와 storage repair 목적. 장애 복구 시에만 사용 |
| `playbooks/ad-dc-failover-test.yml` | DC 장애 전환 테스트. 문서 절차와 확인 변수를 요구 |

## 4. Legacy archive

현재 운영 기준에서 제외한 과거 playbook은 `ansible/archive/legacy/`에 보관한다.
