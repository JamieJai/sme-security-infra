# 전체 재구축 자동화 로드맵

이 문서는 `homelab-infra` Git 저장소만으로 전체 인프라를 다시 구현할 수 있게 만들기 위한 단계별 계획이다.

최종 목표는 다음과 같다.

- 새 운영 노드에서 Git clone 후 최소한의 secret만 주입하면 Terraform과 Ansible로 전체 인프라를 재현한다.
- 운영 중인 환경에서는 안전한 정상화/검증 명령만 반복 실행할 수 있다.
- 파괴적 재구축, 장애 복구, 운영 보정 작업을 명확히 분리한다.

## 목표 상태

```text
Git clone
  -> prerequisites check
  -> secret/material check
  -> terraform init/validate/plan/apply
  -> ansible bootstrap
  -> ansible service orchestration
  -> verify-all
  -> handoff report
```

## 원칙

실행 모드 구분은 `docs/operations/operation-modes.md`를 따른다.

- Terraform은 VM, 디스크, 네트워크, cloud-init 기본값까지만 책임진다.
- Ansible은 OS, AD, Keycloak, Nextcloud, Mail, Wazuh, 보안 정책, 검증을 책임진다.
- `terraform.tfvars`, Terraform state, Ansible vault password, 실제 secret은 Git에 저장하지 않는다.
- 운영 보정 playbook과 재구축/복구 playbook은 같은 자동 실행 경로에 넣지 않는다.
- 전체 설치 스크립트는 기본적으로 dry-run/plan/check 단계를 먼저 제공해야 한다.
- destructive 작업은 명시적 confirm 변수 없이는 실행하지 않는다.

## 1단계: 현재 운영 상태 정상화

목표는 이미 동작 중인 인프라를 반복 검증 가능한 상태로 고정하는 것이다.

우선순위:

1. `verify-all.yml`을 기준 smoke test로 유지한다.
2. AD DNS core A record 관리를 유지하고 PTR/CNAME 확장 여부를 결정한다.
3. Wazuh AI shadow metrics/report를 정기 실행과 retention으로 운영화한다.
4. 완료된 과거 TODO 문서를 정리한다.
5. Nextcloud TLS와 AD secret 관리 방식을 정리한다.

반복 실행 기준:

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/ad-dns-records.yml
ansible-playbook -i inventory/hosts playbooks/verify-all.yml
```

## 2단계: 안전한 운영 오케스트레이션 추가

현재 `ansible/site.yml`은 전체 인프라 진입점이 아니다. 먼저 안전하게 반복 가능한 운영 보정용 entrypoint를 만든다.

후보 파일:

- `ansible/site-baseline.yml`
- `ansible/site-services.yml`
- `ansible/site-security.yml`
- `ansible/site-verify.yml`

초기 포함 후보:

```text
common.yml
ad-dc-chrony.yml
ad-dc-disable-sssd.yml
ad-dc-firewall.yml
ad-dns-records.yml
account-lockout.yml
password-policy.yml
storage-policy.yml
storage-rpc-gssd.yml
keycloak-ldap-ha.yml
keycloak-ldap-ldaps.yml
nextcloud-cron.yml
nextcloud-oidc-sso.yml
nextcloud-oidc-groups.yml
nextcloud-integrations.yml
nextcloud-mail.yml
nextcloud-ad-addressbook.yml
nextcloud-ad-addressbook-schedule.yml
identity-flow-verify.yml
nextcloud-talk.yml
mail-server.yml
dovecot-conf.yml
mail-autoconfig.yml
wazuh-agent-deploy.yml
wazuh-agent-logs.yml
samba-domain-backup.yml
certificate-expiry-monitor.yml
verify-all.yml
```

제외할 항목:

```text
nextcloud-server.yml
rebuild-dc01.yml
additional-dc.yml
ad-server.yml
repair-nextcloud-config.yml
ad-dc-failover-test.yml
rotate-ad-administrator.yml
```

이 항목들은 별도 runbook 또는 명시적 confirm 변수를 요구하는 복구 경로로 유지한다.

## 3단계: 신규 환경 bootstrap 스크립트

신규 운영 노드에서 실행할 wrapper를 추가한다.

후보:

- `scripts/bootstrap-control-node.sh`
- `scripts/terraform-plan.sh`
- `scripts/terraform-apply.sh`
- `scripts/ansible-baseline.sh`
- `scripts/ansible-services.sh`
- `scripts/ansible-agent-deploy.sh`
- `scripts/verify-all.sh`
- `scripts/full-check.sh`
- `scripts/full-apply.sh`

`full-apply.sh`의 기본 흐름:

```text
1. required commands 확인: git, ssh, terraform, ansible, ansible-playbook
2. 민감 파일 존재 확인: terraform/terraform.tfvars, ansible/.vault_pass
3. Terraform fmt/validate/plan 실행
4. 사용자 확인 후 Terraform apply
5. Ansible ping 확인
6. baseline/services/security 순서 실행
7. verify-all 실행
8. 결과 요약 파일 생성
```

초기 버전은 운영 중인 환경을 건드리지 않도록 `plan`과 `verify` 중심으로 만든다. 실제 `apply`는 명시 옵션으로만 실행한다.

## 4단계: Secret 주입 방식 정리

Git만으로 재현 가능하게 하되, secret은 Git에 넣지 않는다.

필요한 정리:

- `terraform/terraform.tfvars.example` 최신화
- Ansible vault 변수 목록 문서화
- `.vault_pass` 배치 방식 문서화
- 신규 환경에서 필요한 secret checklist 작성
- 가능하면 `docs/getting-started/secrets-checklist.md` 추가

최종적으로는 다음 중 하나를 선택한다.

- 로컬 파일 기반: 단순하고 현재 구조와 잘 맞음
- Ansible Vault 중심: Ansible secret에는 적합함
- 별도 secret manager: 더 좋지만 homelab 복잡도가 증가함

현 단계 추천은 로컬 파일 + Ansible Vault 기준을 명확히 문서화하는 것이다.

## 5단계: 완전 재현성 검증

최종 검증은 기존 운영 서버를 망가뜨리지 않는 별도 test namespace 또는 별도 Proxmox node/pool에서 수행한다.

검증 기준:

- 빈 Proxmox target에 Terraform으로 VM 생성 가능
- inventory IP와 Terraform VM IP 일치
- Ansible ping 전체 성공
- AD primary/additional DC 구성과 replication 정상
- Keycloak LDAP/OIDC 정상
- Nextcloud login, cron, mail, addressbook, storage 정상
- Mail SMTP/IMAP 정상
- Wazuh server/agent/log collection 정상
- `verify-all.yml` 통과

## 가까운 다음 작업

1. `ansible/site.yml`을 현재 내용 그대로 두고, 별도 `site-baseline.yml`부터 추가한다.
2. `ad-dns-records.yml`에 PTR/CNAME 확장을 넣을지 설계한다.
3. `scripts/verify-all.sh`와 `scripts/full-check.sh`로 비파괴 검증 경로를 먼저 고정한다.
4. `scripts/full-apply.sh`는 마지막에 만든다.

바로 전체 설치 스크립트부터 만들지 않는 이유는 초기 구축용 destructive 작업과 운영 보정 작업이 아직 일부 섞여 있기 때문이다. 먼저 안전한 entrypoint를 만든 뒤, 그 entrypoint들을 wrapper script가 순서대로 호출하게 만든다.
