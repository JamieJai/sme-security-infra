# 운영 모드와 실행 기준

이 문서는 `homelab-infra`에서 초기 구축, 운영 보정, 재배포/복구 작업을 구분하는 기준이다.

## 1. 비파괴 검증

목적: 현재 운영 상태와 Terraform drift를 확인한다. 기본적으로 인프라를 변경하지 않는다.

```bash
./scripts/full-check.sh
```

포함 단계:

```text
terraform init/fmt/validate/plan
ansible ping
AD DNS record reconcile
verify-all.yml
```

## 2. 운영 baseline 보정

목적: OS 공통 기준, AD DNS/forwarder, AD 정책, storage policy, backup/timer 같은 운영 기준을 재적용한다.

```bash
./scripts/ansible-baseline.sh
```

특징:

- `common_upgrade_packages: false`로 실행한다.
- 의도치 않은 dist-upgrade를 하지 않는다.
- AD DNS A/PTR/CNAME과 DNS forwarder를 관리한다.

## 3. 운영 서비스 보정

목적: 이미 설치된 Keycloak, Nextcloud, Mail, Wazuh 설정을 운영 기준으로 재적용한다.

```bash
./scripts/ansible-services.sh
```

포함 예:

```text
Wazuh/Grafana apt repository hygiene
Keycloak LDAP HA/LDAPS
Nextcloud OIDC/groups/mail/addressbook/Talk
Dovecot/mail autoconfig
Wazuh agent log collection
Wazuh custom detections
```

제외 항목:

```text
wazuh-agent-deploy.yml
mail-server.yml
nextcloud-server.yml
```

위 항목들은 설치/재배포 성격이 있으므로 일반 운영 보정 경로에 넣지 않는다.

## 4. Agent 재배포

목적: Wazuh agent를 설치하거나 고정 버전으로 재조정한다.

```bash
./scripts/ansible-agent-deploy.sh
```

주의:

- `wazuh-agent=4.10.4-1` 설치와 `allow_downgrade`가 포함되어 있다.
- 일반 서비스 보정이 아니라 agent 재배포 목적으로만 실행한다.

## 5. 전체 적용

목적: Terraform apply부터 Ansible baseline/services/verify까지 한 번에 진행한다.

```bash
./scripts/full-apply.sh
```

안전장치:

- 기본적으로 단계별 `APPLY` 입력을 요구한다.
- `RUN_AGENT_DEPLOY=false`가 기본값이다.
- Wazuh agent 재배포는 명시적으로 `RUN_AGENT_DEPLOY=true`일 때만 실행한다.

자동 승인은 명시적으로만 사용한다.

```bash
AUTO_APPROVE=true ./scripts/full-apply.sh
```

## 6. 위험/복구 전용

다음 playbook은 운영 보정이나 전체 적용 기본 경로에 넣지 않는다.

```text
playbooks/nextcloud-server.yml
playbooks/rebuild-dc01.yml
playbooks/additional-dc.yml
playbooks/ad-server.yml
playbooks/repair-nextcloud-config.yml
playbooks/ad-dc-failover-test.yml
playbooks/rotate-ad-administrator.yml
```

실행 전에는 별도 runbook, 백업, confirm 변수, 영향 범위 확인이 필요하다.

## 권장 일상 운영 순서

일반 점검:

```bash
./scripts/full-check.sh
```

운영 기준 보정:

```bash
./scripts/ansible-baseline.sh
./scripts/ansible-services.sh
./scripts/verify-all.sh
```

신규 구축 또는 큰 변경:

```bash
./scripts/full-apply.sh
```
