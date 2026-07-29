# Toss IT Manager Application Evidence

기준일: `2026-07-29`

이 문서는 현재 공개된 토스 Community IT Manager 역할을 기준으로 저장소의
구현 증거와 공백을 연결한다. 지원서에서는 아래 내용을 개인 homelab 프로젝트로
명시하며 회사 production 운영 경험으로 표현하지 않는다.

- [IT Manager 통합 공고](https://toss.im/career/job-detail?job_id=7774167003)
- [토스증권 IT Manager 상세 공고](https://toss.im/career/job-detail?job_id=4523521003)

## 포지셔닝

계정 생성, PC 설정, 장애 대응을 각각 처리하는 데서 끝내지 않고 사용자가 업무를
시작할 수 있는 상태를 검증하고, 실패 원인과 운영 결과를 증거로 남기는 IT 운영
자동화를 구현했다.

## 증거 상태 정의

| 상태 | 의미 |
|---|---|
| Verified | 개인 live lab에서 end-to-end 결과를 확인하고 운영 증적을 남김 |
| Implemented | 코드와 runbook이 있으며 제한된 fixture/dry-run/pilot 검증을 수행 |
| Gap | 실제 장비, tenant 또는 사용자 운영 경험이 없어 지원서에서 경험으로 주장하지 않음 |

## JD-증거 매트릭스

| 공고 요구사항 | 상태 | 저장소 증거 | 지원서 표현 |
|---|---|---|---|
| 네트워크·서버·내부 시스템 운영 | Verified | [Architecture](../architecture.md), [verify-all](../../ansible/playbooks/verify-all.yml) | Proxmox 기반 AD/IAM/협업/Mail/SIEM 환경을 구성하고 통합 health check 운영 |
| 계정 및 권한 관리 | Verified | [onboard script](../../scripts/onboard-employee.sh), [offboard pilot](employee-offboarding-lifecycle-pilot.md) | AD 그룹을 권한 원천으로 사용하고 전용 test identity의 온보딩·차단·복구·재차단을 live 검증 |
| Windows endpoint 운영 | Verified | [ODJ script](../../scripts/generate-windows-odj-package.sh), [runbook](../services/endpoint-management.md) | ODJ, 자산 등록, Wazuh, pilot 앱 배포 및 reboot 검증 |
| 업무 협업 도구 운영 | Verified | Nextcloud, Talk, Postfix/Dovecot runbook | 개인 lab의 파일·메신저·메일 연동 운영으로 한정 |
| 사용자 IT 이슈 진단 | Implemented | [diagnose script](../../scripts/helpdesk-diagnose.sh), [scenario](../operations/helpdesk-scenarios.md) | 6개 업무 장애를 read-only 진단과 후속 조치 workflow로 표준화 |
| 반복 업무 자동화·프로세스 개선 | Verified | onboarding, health report, endpoint deployment scripts | 실행뿐 아니라 검증·리포트·SQLite 기록까지 자동화 |
| 보안 요구사항을 고려한 운영 | Verified | Wazuh, 최소 권한 SMB, secret guard, egress guard | 일반 사용자 권한 상승 없이 앱 배포하고 보안 로그와 rollback 조건 운영 |
| 문제 데이터화와 근본 해결 | Verified | `.codex/mcp/homelab_ops.sqlite`, Markdown reports, Wazuh incident handoff | 결과 상태와 증적을 저장하고 실패 후 배포 gate를 추가 |
| macOS 이해 및 운영 | Gap | 설계 문서만 존재 | 실제 macOS/MDM 운영 경험으로 주장하지 않음 |
| Google Workspace/Slack SaaS 운영 | Gap | Slack/Notion integration path는 있으나 production tenant 없음 | API 연계 경험과 production administration 경험을 분리 |
| 물리 PC·복합기·NAC/DLP | Gap | Windows VM과 보안 lab 중심 | 실제 사무실 장비 운영 경험으로 주장하지 않음 |
| 사용자 SLA·MTTR | Gap | scenario와 timestamp 기록 구조는 있으나 실제 사용자 표본 없음 | 실사용 지표가 아닌 workflow 설계로 표현 |

## 이력서용 프로젝트 요약

### 기업형 IT 운영 자동화 플랫폼 구축

**개인 프로젝트 / 설계·구축·운영 자동화 전 과정 수행**

- Samba AD 계정과 부서 그룹 생성부터 Keycloak SSO, Nextcloud 권한, Mail,
  Wazuh baseline 검증까지 연결한 입사자 온보딩 workflow 구현
- 삭제 대신 AD disable, 부서 그룹 회수, Keycloak session revoke, 자산
  `recovery_pending` 전환을 수행하는 승인형 오프보딩 workflow 구현 및 fixture 검증
- 사용자에게 관리자 암호를 제공하지 않고 승인 앱을 설치하도록 컴퓨터 계정 전용
  SMB share와 SYSTEM scheduled task를 설계하고 Windows pilot에서 reboot까지 검증
- Windows EventChannel 수집 장애와 Wazuh receiver 장애를 복구하고 TCP 1514 및
  8개 managed agent Active 확인을 배포 성공 조건으로 자동화
- Ansible 반복 적용, Terraform plan, Markdown report, SQLite operation record,
  secret scan을 통해 변경 결과와 감사 증적을 관리

## 문제 해결 사례 1: Windows 표준 앱 배포

**상황**

일반 사용자가 업무용 앱을 설치해야 하지만 local administrator 권한이나 관리자
암호를 제공하면 endpoint 권한 경계가 무너지는 문제를 설정했다.

**판단**

사용자 권한을 높이는 대신 승인된 설치만 컴퓨터의 SYSTEM context에서 실행하고,
전체 PC가 아닌 pilot security group으로 범위를 제한했다.

**실행**

- 사용자 share와 컴퓨터 installer share 분리
- `Domain Computers`에는 installer read/traverse만 허용
- Nextcloud Desktop/Talk silent install 및 detection 구현
- `ODJ-VERIFY01`만 pilot group에 포함

**결과**

실제 앱 설치, 즉시 실행, reboot 후 ONSTART 실행, transcript, detection,
operations DB 기록을 확인했다. 반복 실행에서 불필요한 재설치가 발생하지 않도록
수렴 조건도 보강했다.

**증거**

- [Endpoint 앱 배포 사례](endpoint-app-deployment-system-install.md)
- [Pilot scope playbook](../../ansible/playbooks/endpoint-app-deployment-scope.yml)
- [Bootstrap task playbook](../../ansible/playbooks/endpoint-app-bootstrap-task.yml)

## 문제 해결 사례 2: Wazuh Windows 수집 장애

**상황**

Windows EventChannel 중앙 수집 적용 후 agent가 shared config를 처리하지 못했고,
manager 재시작 과정에서는 `wazuh-remoted`가 종료됐지만 systemd 상위 서비스는
active로 보였다.

**원인**

- shared sync directory 안의 Ansible timestamp backup 파일명에 Windows에서
  허용하지 않는 colon이 포함됨
- 기존 배포 검증이 manager 상위 service 상태만 확인하고 TCP 1514 receiver와
  agent 재접속을 확인하지 않음

**실행**

- backup을 sync directory 밖으로 이동하고 unsafe `*~` 파일 검증 추가
- custom rule의 fixture/live decoder와 built-in parent chain 재검토
- restart handler를 즉시 적용한 뒤 TCP 1514와 agent별 Active 상태를 확인

**결과**

Windows endpoint 2대가 shared config에 다시 수렴했고, 최종 반복 실행은
`changed=0`으로 끝났다. 8개 managed agent가 모두 Active인 경우에만 배포가
성공하도록 조건을 강화했다.

**증거**

- [Wazuh 운영 handoff](../archive/session-handoffs/session-handoff-2026-07-28-kali-egress-enabled.md)
- [Windows agent playbook](../../ansible/playbooks/wazuh-agent-windows.yml)
- [Custom detection playbook](../../ansible/playbooks/wazuh-custom-detections.yml)

## 문제 해결 사례 3: 입사자 온보딩의 완료 기준

**상황**

AD 계정 생성 성공만으로는 사용자가 SSO, 부서 폴더, 메일을 실제로 사용할 수
있는지 알 수 없고 부분 실패가 운영자에게 남지 않는 문제가 있다.

**판단**

온보딩 완료를 계정 생성 return code가 아니라 서비스별 검증과 운영 증적의
존재로 정의했다. 자동 삭제는 잘못된 계정을 더 위험하게 만들 수 있어 v1
rollback에서 제외했다.

**실행**

- 입력값과 부서 매핑 검증
- AD 사용자·그룹·mail attribute 생성
- Keycloak, Nextcloud, Mail, Wazuh baseline 검증
- Markdown report와 SQLite 상태 기록
- Slack 실패는 계정 생성을 되돌리지 않고 `partial`로 분류

**결과**

성공, 부분 성공, 실패를 구분하고 후속 조치가 가능한 workflow를 구현했다.
비밀번호는 CLI argument와 report에 남기지 않는다.

**증거**

- [Onboarding script](../../scripts/onboard-employee.sh)
- [Onboarding verify playbook](../../ansible/playbooks/employee-onboarding-verify.yml)
- [Onboarding runbook](../operations/employee-onboarding-runbook.md)

## 면접에서 먼저 밝힐 제한

1. 모든 사용자는 test identity이며 실제 임직원 지원 건수가 아니다.
2. endpoint fleet 검증은 Windows pilot 중심이며 macOS 실기는 아직 없다.
3. Nextcloud/Talk/Mail은 협업 도구 운영 원리를 검증하기 위한 self-hosted 환경이다.
4. Google Workspace, 물리 복합기, NAC/DLP의 production 운영 경험은 주장하지 않는다.
5. Kali는 Wazuh 탐지 품질 확인용으로 범위를 고정했으며 침투 경험을 IT Manager
   핵심 역량처럼 내세우지 않는다.
6. 오프보딩 AD/group/asset lifecycle은 전용 test identity로 live 검증했지만
   실제 active Keycloak session과 provision된 Nextcloud user branch는 검증하지 않았다.

## 지원 전 남은 외부 실습

| 우선순위 | 실습 | 완료 기준 |
|---:|---|---|
| 1 | macOS 실제 장비 baseline | FileVault, 표준/관리자 계정 분리, inventory, 복구 절차 |
| 2 | SaaS test tenant lifecycle | 사용자·그룹·MFA·session revoke·audit log |
| 3 | Helpdesk 지표 | 실제 또는 명확히 표시한 모의 티켓에서 priority, resolution time, recurrence 집계 |
| 4 | 자산 lifecycle | 지급, 사용자 매핑, 수리, 회수, wipe, 폐기 상태 전이 |
