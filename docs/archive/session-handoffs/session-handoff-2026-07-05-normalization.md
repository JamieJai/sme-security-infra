# Session Handoff - 2026-07-05 Normalization

이번 세션은 전체 재구축 자동화로 가기 전에 현재 운영 인프라를 반복 적용/검증 가능한 상태로 정상화하는 데 집중했다.

## 완료한 작업

- `scripts/verify-all.sh`를 추가해 `ansible ping`, AD DNS A record 보정, `verify-all.yml`을 한 번에 실행할 수 있게 했다.
- `ansible/site-baseline.yml`과 `scripts/ansible-baseline.sh`를 추가해 안전한 운영 baseline entrypoint를 만들었다.
- `common.yml`이 단독 실행될 때 `group_vars/all.yml`을 명시 로드하도록 보정했다.
- `common` role의 apt 작업을 cache update와 package upgrade로 분리했다.
  - 기본 직접 실행은 기존처럼 upgrade 가능하다.
  - `site-baseline.yml`에서는 `common_upgrade_packages: false`로 dist-upgrade를 제외한다.
- Samba AD DNS 외부 forwarder 관리용 `playbooks/ad-dns-forwarder.yml`을 추가했다.
- `dc01`, `dc02`의 `samba_conf_path` 기준을 실제 사용 경로인 `/etc/samba/smb.conf`로 맞췄다.
- `dc01`의 외부 DNS 해석 실패를 고쳤고, 그 영향으로 `storage01`의 apt DNS 실패도 해소했다.
- `docs/getting-started/full-rebuild-roadmap.md`를 추가해 Git 저장소 기반 전체 재현 목표와 단계별 자동화 계획을 정리했다.
- `docs/reference/ansible-playbook-catalog.md`에 AD DNS forwarder playbook을 추가했다.

## 확인한 문제와 조치

- 문제: `site-baseline.yml` 실행 시 `domain_name` 변수가 undefined로 실패했다.
  - 조치: `playbooks/common.yml`에 `vars_files: ../group_vars/all.yml` 추가, wrapper에서 `-e @group_vars/all.yml` 명시.
- 문제: baseline 실행 중 `dc01`, `storage01`의 apt cache update가 DNS 해석 실패로 실패했다.
  - 조치: Samba AD DNS forwarder를 `8.8.8.8`로 IaC 관리하고 `dc01` Samba AD DC를 재시작해 반영.
- 문제: `dc01` Samba 재시작 직후 `dc02`의 `ForestDnsZones` replication이 1회 실패 상태를 보고했다.
  - 조치: `samba-tool drs replicate dc02 dc01 DC=ForestDnsZones,DC=toss,DC=lan -P`로 동기화했고 이후 `[ALL GOOD]` 확인.

## 최종 검증 결과

- `./scripts/ansible-baseline.sh`: 최종 통과
  - `failed=0`, `unreachable=0`
- `./scripts/verify-all.sh`: 최종 통과
  - `failed=0`, `unreachable=0`
- AD replication: `dc01`, `dc02` 모두 `[ALL GOOD]`
- 외부 DNS:
  - `dc01`에서 `archive.ubuntu.com` 해석 성공
  - `storage01`에서 `archive.ubuntu.com` 해석 성공
- apt update:
  - `dc01`, `storage01` 모두 성공
  - 남은 경고: Wazuh apt key가 legacy trusted.gpg에 있다는 deprecation warning

## 다음 우선순위

1. Wazuh apt repository key를 `/etc/apt/keyrings` 기반으로 이전한다.
2. AD DNS PTR/CNAME 관리 여부를 결정하고 `ad-dns-records.yml`을 확장한다.
3. `verify-all.yml`에 AD DNS forwarder/external resolution 검증을 추가한다.
4. `scripts/terraform-plan.sh`, `scripts/ansible-services.sh`처럼 wrapper 계층을 점진적으로 늘린다.
5. 모든 wrapper가 안정화된 뒤 `scripts/full-apply.sh`를 만든다.

## 바로 실행할 명령

```bash
cd /home/sysadmin/homelab-infra
./scripts/ansible-baseline.sh
./scripts/verify-all.sh
```

## 추가 고도화 - apt/DNS/wrapper

- Wazuh apt repository를 legacy `apt_key`에서 `signed-by=/usr/share/keyrings/wazuh.gpg` 방식으로 이전했다.
- `wazuh-agent-deploy.yml`도 앞으로 legacy `apt_key`를 다시 만들지 않도록 수정했다.
- `keycloak`의 Grafana apt repository도 공식 문서 기준 `signed-by=/etc/apt/keyrings/grafana.asc` 방식으로 이전했다.
- 전체 호스트 `apt-get update`에서 `legacy trusted.gpg` 경고가 사라진 것을 확인했다.
- AD DNS를 A record만이 아니라 reverse zone/PTR/CNAME까지 관리하도록 확장했다.
  - CNAME: `mail -> mail01`, `autoconfig -> mail01`, `keycloak-ldap-ha -> keycloak`
  - PTR: core host IP 전체
- `verify-all.yml`에 AD DNS 외부 해석, PTR, CNAME 검증을 추가했다.
- `ansible/site-services.yml`과 `scripts/ansible-services.sh`를 추가했다.
- `scripts/terraform-plan.sh`를 추가했고 `No changes` plan을 확인했다.

## 추가 고도화 - service entrypoint 정리

- `ansible/site-services.yml`을 운영 보정용으로 다듬었다.
  - 일반 재적용에서 `wazuh-agent-deploy.yml`은 제외했다. 고정 버전 설치/다운그레이드 가능성이 있어 별도 경로로 분리했다.
  - `mail-server.yml`은 변수 파일 경로를 `../group_vars/vault.yml`로 보정했다.
- `ansible/site-agent-deploy.yml`과 `scripts/ansible-agent-deploy.sh`를 추가했다.
- `scripts/full-check.sh`를 추가했다. 이 스크립트는 Terraform plan과 전체 verify만 수행하는 비파괴 검증 경로다.
- `scripts/full-check.sh` 실행 결과:
  - Terraform: `No changes`
  - Ansible verify: `failed=0`, `unreachable=0`

## 추가 완료 - apply path 정리

체크리스트 결과:

- [x] `scripts/ansible-services.sh` 실제 적용 검증
  - 최종 `failed=0`, `unreachable=0`
  - 적용 후 `scripts/verify-all.sh`도 `failed=0`, `unreachable=0`
- [x] `scripts/full-apply.sh` 설계/작성
  - Terraform plan/apply, baseline, services, optional agent deploy, verify 순서
  - 단계별 `APPLY` 확인 입력 필요
  - `RUN_AGENT_DEPLOY=false` 기본값
- [x] `docs/getting-started/secrets-checklist.md` 추가
- [x] `docs/operations/operation-modes.md` 추가

남은 개선 후보:

- 일부 Keycloak/Nextcloud playbook은 반복 실행 시 매번 `changed`로 표시된다. 기능 검증은 통과하지만 idempotency 개선 여지가 있다.
- `mail-server.yml` 변수 경로는 `../group_vars/vault.yml`로 보정했다.

## 다음 세션 전략

우선순위는 기능 추가보다 idempotency와 재현성 완성이다.

1. 서비스 playbook idempotency 개선
   - `ansible-services.sh`는 통과하지만 Keycloak/Nextcloud 일부 task가 반복 실행 시 매번 `changed`로 표시된다.
   - 우선 대상: `keycloak-ldap-ldaps.yml`, `nextcloud-oidc-sso.yml`, `nextcloud-oidc-groups.yml`, `nextcloud-integrations.yml`, `nextcloud-ad-addressbook.yml`.
   - 목표: 재실행 시 실제 변경이 없으면 `changed=0`에 가깝게 만든다.

2. 문서 2차 정리
   - `docs/README.md`를 기준으로 실제 사용 흐름을 하루 써보고 누락/중복을 줄인다.
   - `iac-runbook.md`, `initial-build-guide.md`, `full-rebuild-roadmap.md`의 중복 문단을 정리한다.
   - archive 문서는 역사 기록으로 두고 현재 문서에서 직접 참조하지 않는다.

3. `full-apply.sh` dry-run UX 개선
   - 현재 `full-apply.sh`는 단계별 confirm을 둔 실제 적용 경로다.
   - 다음에는 `--plan-only` 또는 `MODE=check` 같은 안전 모드를 추가할지 검토한다.

4. 신규 환경 재현성 리허설 준비
   - 실제 빈 Proxmox target에서 바로 실행하기 전, secret checklist와 terraform tfvars example을 비교한다.
   - inventory와 Terraform VM map의 IP/host 일치 검증을 script로 만들 후보가 있다.

현재 종료 기준:

- `scripts/ansible-services.sh`: 통과
- `scripts/verify-all.sh`: 통과
- `scripts/full-check.sh`: 통과
- Terraform plan: `No changes`
