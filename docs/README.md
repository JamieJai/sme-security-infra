# Homelab Infra 문서 안내

이 디렉터리는 `homelab-infra`를 구축, 운영, 검증, 복구하기 위한 문서를 역할별로 나눈다. 처음 보는 경우 이 문서에서 시작한다.

## 먼저 볼 문서

| 상황 | 볼 문서 |
|---|---|
| 전체 구조를 이해하고 싶다 | [architecture.md](architecture.md) |
| 새 환경에서 처음 구축한다 | [getting-started/initial-build-guide.md](getting-started/initial-build-guide.md) |
| Git clone 후 필요한 secret을 준비한다 | [getting-started/secrets-checklist.md](getting-started/secrets-checklist.md) |
| 어떤 스크립트를 언제 실행할지 알고 싶다 | [operations/operation-modes.md](operations/operation-modes.md) |
| 현재 상태를 점검한다 | [operations/verification-runbook.md](operations/verification-runbook.md) |
| MCP 기반 IT Manager 자동화 로드맵을 본다 | [operations/mcp-roadmap.md](operations/mcp-roadmap.md) |
| IT Manager 플랫폼 방향성을 본다 | [operations/it-manager-platform-roadmap.md](operations/it-manager-platform-roadmap.md) |
| 신입사원 온보딩 운영 절차를 본다 | [operations/employee-onboarding-runbook.md](operations/employee-onboarding-runbook.md) |
| 신규 입사자용 IT 사용 가이드를 본다 | [getting-started/employee-it-onboarding.md](getting-started/employee-it-onboarding.md) |
| 전체 자동화 목표를 본다 | [getting-started/full-rebuild-roadmap.md](getting-started/full-rebuild-roadmap.md) |
| Ansible playbook 목록과 위험도를 확인한다 | [reference/ansible-playbook-catalog.md](reference/ansible-playbook-catalog.md) |
| Terraform 기준을 확인한다 | [reference/terraform-runbook.md](reference/terraform-runbook.md) |
| Windows/macOS 단말 관리 방향을 본다 | [services/endpoint-management.md](services/endpoint-management.md) |

## 디렉터리 구조

```text
docs/
  README.md
  architecture.md
  getting-started/   # 신규 구축, secret, 전체 재현 로드맵
  operations/        # 운영 모드, IaC 실행 순서, 검증
  reference/         # Terraform/Ansible 참조
  services/          # AD/Keycloak/Nextcloud/Mail/Wazuh 등 서비스별 문서
  recovery/          # 장애 시험과 복구 절차
  archive/           # 과거 session handoff와 작업 기록
```

## 자주 쓰는 명령

비파괴 전체 점검:

```bash
./scripts/full-check.sh
```

운영 기준 보정:

```bash
./scripts/ansible-baseline.sh
./scripts/ansible-services.sh
./scripts/verify-all.sh
```

전체 적용:

```bash
./scripts/full-apply.sh
```

Wazuh agent 설치/재배포:

```bash
./scripts/ansible-agent-deploy.sh
```

## 문서 작성 기준

- 신규 구축과 운영 보정은 분리해서 쓴다.
- 위험/복구 작업은 `recovery/` 또는 별도 runbook에 둔다.
- 과거 작업 기록은 `archive/session-handoffs/`에 둔다.
- 루트 `docs/`에는 안내 문서와 전체 아키텍처만 둔다.
