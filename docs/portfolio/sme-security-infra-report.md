# [Project 07] 중소기업형 보안 인프라 구축

*"AD, SSO, 협업 서비스, 메일, SIEM을 하나의 운영 흐름으로 묶어 실제 기업 IT 환경에 가까운 보안 인프라를 구현한 프로젝트"*

## 1. 개요 (Overview)

- **목표:** 중소기업에서 현실적으로 필요한 계정 관리, 권한 제어, 협업 서비스, 메일, 보안 관제, 운영 자동화를 하나의 내부 인프라로 구성한다.
- **핵심 방향:** 단순히 서버를 여러 대 설치하는 것이 아니라, `신원 -> 권한 -> 업무 서비스 -> 로그 수집 -> 검증/보고`까지 이어지는 보안 운영 흐름을 만든다.
- **핵심 성과:**
  - Samba AD 기반 중앙 계정/그룹 관리 체계 구축
  - Keycloak LDAP federation과 OIDC를 통한 SSO/IAM 레이어 구성
  - Nextcloud, Mail, Storage를 AD 그룹 기반으로 연동
  - Wazuh SIEM을 통해 AD, IAM, 협업, 메일, 스토리지 로그 수집
  - Ansible 기반 검증, 리포트, SQLite 기록, Slack/Notion 연계 기반 마련

---

## 2. 문제 발견 (Problem Identification)

### **[현상]**

개별 서비스를 따로 구축하는 방식은 처음에는 빠르게 보이지만, 실제 운영 관점에서는 다음 문제가 발생한다.

- 계정이 서비스마다 따로 관리되어 입사/퇴사/부서 이동 시 권한 누락이 발생하기 쉽다.
- 파일 공유, 메일, SSO, 보안 로그가 서로 분리되어 장애나 침해 의심 상황을 추적하기 어렵다.
- 보안 장비가 있어도 어떤 계정이 어떤 서비스에 접근했고, 어떤 로그가 위험 신호인지 연결하기 어렵다.
- 수동 점검에 의존하면 인프라 상태를 지속적으로 증명하기 어렵고, 운영 이력이 남지 않는다.

### **[임팩트]**

- **권한 관리 리스크:** 퇴사자 계정, 부서 변경 후 잔여 권한, 공유 폴더 오노출 가능성 증가
- **침해 대응 지연:** AD 로그인 실패, 메일 인증 실패, Nextcloud 접근, 파일 변경 이벤트가 분리되어 상관관계 분석이 어려움
- **운영 품질 저하:** 사람이 매번 수동으로 확인하면 같은 작업도 실행자에 따라 결과가 달라짐
- **포트폴리오 한계:** 단순 설치 기록만으로는 실제 IT 운영 역량을 설명하기 어려움

---

## 3. 해결 과정 (Implementation)

### **[기술적 조치 1: Samba AD를 중심으로 한 Identity 기준점 구축]**

인프라의 기준을 개별 서비스 계정이 아니라 AD 사용자와 그룹으로 통일했다. `toss.lan` 도메인을 기준으로 `HR_Staff`, `Finance_Staff`, `IT_Admins`, `Security_Team`, `Server_Admins` 같은 그룹을 정의하고, 각 서비스가 이 그룹 정보를 활용하도록 설계했다.

- `dc01`, `dc02`를 Samba AD DC로 구성하여 DNS, Kerberos, LDAP, SYSVOL 기반을 마련
- `dc02`를 active DC와 FSMO 기준점으로 두고 AD 쓰기 작업 대상을 명확히 분리
- 사용자 속성에는 mail/displayName을 포함하여 SSO, 주소록, 메일 흐름의 기준 데이터로 활용
- 신규 입사자 온보딩은 `scripts/onboard-employee.sh`와 `ad-onboard-user.yml`을 통해 AD 계정 생성, 그룹 부여, mail attribute 설정까지 표준화

이 설계의 핵심은 "권한은 서비스 화면에서 따로 주는 것이 아니라 AD 그룹에서 출발한다"는 점이다.

### **[기술적 조치 2: Keycloak과 OIDC를 통한 SSO/IAM 레이어 구성]**

AD는 계정의 원천이지만, 웹 서비스 로그인과 토큰 기반 접근 제어에는 IAM 레이어가 필요하다. 이를 위해 Keycloak의 Samba AD LDAP federation을 구성하고, Nextcloud는 OIDC client로 연결했다.

목표 흐름:

```text
Samba AD users/groups/mail/displayName
  -> Keycloak Samba-AD LDAP federation
  -> Keycloak nextcloud-oidc OIDC client
  -> groups claim
  -> Nextcloud user_oidc provider
  -> Nextcloud group provisioning / storage ACL / addressbook
```

구현 포인트:

- Keycloak realm `homelab` 구성
- LDAP federation `Samba-AD`로 AD 사용자 인증 연동
- `nextcloud-oidc` client와 `nextcloud-groups` mapper 구성
- Nextcloud는 `groups` claim을 읽어 그룹 provisioning과 login restriction 적용
- AD 그룹이 바뀌면 다음 로그인 시 Nextcloud 그룹과 storage 접근 범위가 갱신되는 구조로 설계

이 과정에서 SSO는 단순한 로그인 편의 기능이 아니라, AD 그룹을 웹 서비스 권한으로 전달하는 보안 제어 지점이 되었다.

### **[기술적 조치 3: Nextcloud, Mail, Storage를 업무 서비스 계층으로 통합]**

Nextcloud는 파일 협업과 사용자 포털 역할을 맡고, Mail은 Postfix/Dovecot 기반으로 내부 메일 서비스를 담당한다. Storage는 부서별 mount를 분리하고 Nextcloud 그룹 제한과 연결했다.

구성 흐름:

```text
AD group
  -> Keycloak groups claim
  -> Nextcloud group provisioning
  -> Department external storage mount
```

부서별 접근 모델:

| Department | AD group | Nextcloud mount |
|---|---|---|
| HR | `HR_Staff` | `/HR` |
| Finance | `Finance_Staff` | `/Finance` |
| IT | `IT_Admins` | `/IT` |
| Security | `Security_Team` | `/Security` |

Mail 흐름:

```text
Samba AD user mail attribute
  -> Postfix virtual mailbox map
  -> Dovecot IMAP/LDAPS auth
  -> Nextcloud Mail app
```

메일 비밀번호를 Ansible이나 Vault에 수집하지 않기 위해, IaC는 서버와 앱 연결성만 보장하고 사용자가 autoconfig를 통해 직접 계정을 추가하는 방식으로 설계했다. 이 부분은 자동화보다 보안 원칙을 우선한 판단이다.

### **[기술적 조치 4: Wazuh SIEM을 통한 보안 가시성 확보]**

보안 인프라에서 중요한 것은 서비스가 "돌아간다"가 아니라, 이상 징후를 볼 수 있고 설명할 수 있는 상태다. Wazuh를 SIEM 기준점으로 두고 AD, Keycloak, Nextcloud, Mail, Storage 로그를 수집하도록 구성했다.

수집 기준:

- `dc01`, `dc02`: journald, Samba AD 로그
- `keycloak`: 로그인, LDAP federation, admin 이벤트
- `nextcloud`: app log, Apache access/error, journald
- `mail01`: Postfix/Dovecot mail log, auth log
- `storage01`: Samba/SMB 로그, journald
- 전체 서버: package log, active response log, baseline FIM

운영 고도화:

- Wazuh 4.10.4 component hold
- Wazuh API loopback bind
- 내부망 기준 UFW 제한
- dashboard/indexer/API TLS와 private key 권한 검증
- `Security_Team` analyst, `Wazuh_ReadOnly` read-only 역할 분리 설계
- custom rule ID 대역과 fixture 기반 탐지 테스트 설계

이전 프로젝트에서 수행했던 brute-force, 내부자 파일 변경, 피싱/메일 로그 상관관계 분석 경험을 이번 구조에서는 운영 가능한 탐지 체계로 확장하는 방향으로 정리했다.

### **[기술적 조치 5: Ansible과 MCP 기반 운영 자동화]**

인프라 운영은 구축보다 반복 검증이 더 중요하다. 이를 위해 Ansible playbook과 script를 업무 단위 workflow로 묶었다.

대표 workflow:

- `scripts/onboard-employee.sh`
  - AD 계정 생성
  - 부서 그룹 부여
  - mail attribute 설정
  - 온보딩 전용 검증
  - AD/Keycloak/Nextcloud/Mail/Wazuh baseline 검증
  - Markdown report 생성
  - SQLite operations record 저장
  - Slack 알림

- `scripts/verify-and-report.sh`
  - `verify-all.yml` 실행
  - IT health Markdown report 생성
  - SQLite 기록
  - Slack 알림
  - 필요 시 Notion publish

- `scripts/generate-windows-ad-join-package.sh`
  - 사번 기반 Windows AD Join package 생성
  - package에는 domain join credential이나 token을 포함하지 않음
  - v2에서는 Offline Domain Join으로 확장 예정

여기서 중요한 변화는 "playbook을 실행할 수 있다"가 아니라, "입사자 온보딩", "IT health report", "PC AD join" 같은 실제 IT 업무 단위로 자동화가 묶였다는 점이다.

---

## 4. 보안 아키텍처 설계 (Current Architecture)

현재 구성은 다음 역할로 나뉜다.

| 영역 | 구성 요소 | 역할 |
|---|---|---|
| Identity | Samba AD | 사용자, 그룹, DNS, Kerberos, LDAP 기준점 |
| IAM | Keycloak | LDAP federation, OIDC, SSO, group claim |
| Collaboration | Nextcloud, Talk | 파일 협업, 내부 커뮤니케이션, 사용자 포털 |
| Mail | Postfix, Dovecot | 내부 메일 송수신, IMAP/SMTP, LDAPS 인증 |
| Storage | NFS/SMB, Nextcloud external storage | 부서별 파일 접근 제어 |
| Security Visibility | Wazuh | 로그 수집, 탐지, 대시보드, hardening |
| Operations | Ansible, scripts, MCP | 적용, 검증, 리포트, 기록, 알림 |
| Evidence | Markdown, SQLite | 자동화 실행 결과와 감사 증적 |

인프라의 중심 흐름:

```text
신입사원 온보딩 요청
  -> AD 계정/그룹/mail 속성 생성
  -> Keycloak LDAP/OIDC 흐름 검증
  -> Nextcloud group/storage/mail baseline 검증
  -> Wazuh 로그 수집 baseline 검증
  -> Markdown report 생성
  -> SQLite operations 기록
  -> Slack/Notion/GitOps로 운영 증적 확장
```

---

## 5. 트러블슈팅 및 설계 판단 (Trouble Shooting)

### **[자동화보다 비밀번호 보호를 우선한 Mail 계정 등록 방식]**

- **문제:** Nextcloud Mail 앱의 사용자별 IMAP 계정 자동 등록에는 사용자 메일 비밀번호가 필요하다.
- **위험:** 자동화를 위해 비밀번호를 Ansible 변수나 Vault에 수집하면, 운영자가 사용자 비밀번호를 보관하는 구조가 된다.
- **판단:** IaC는 Mail 앱과 서버 연결성만 보장하고, 사용자별 계정 등록은 autoconfig를 통해 사용자가 직접 수행하도록 설계했다.
- **배움:** 모든 자동화가 좋은 것은 아니며, 보안 인프라에서는 자동화 범위와 비밀정보 취급 범위를 분리해야 한다.

### **[AI 기반 보안 분석의 권한 경계 설정]**

- **문제:** Wazuh alert를 AI로 분석하면 요약과 분류에는 도움이 되지만, AI 결과만으로 자동 차단을 수행하면 오탐으로 인한 운영 장애가 발생할 수 있다.
- **조치:** `wazuh-ai-shadow`는 read-only alert 수집, SQLite WAL spool, deterministic enrichment만 수행한다.
- **제한:** 외부 LLM, Wazuh write API, SSH/shell 권한, 자동 계정 잠금, 방화벽 차단은 비활성화한다.
- **배움:** AI는 의사결정 보조와 triage에는 유용하지만, 운영 변경 권한은 deterministic rule과 승인된 playbook 경계 안에 둬야 한다.

### **[AD Join 패키지에서 Credential을 제외한 이유]**

- **문제:** 신입사원 PC를 빠르게 도메인에 가입시키려면 join script 자동화가 필요하지만, script에 domain join credential을 넣으면 유출 위험이 커진다.
- **조치:** v1 package는 DNS 확인과 `Add-Computer` 실행을 자동화하되, credential은 `Get-Credential`로 실행 시 입력받는다.
- **향후:** v2에서는 Offline Domain Join blob을 장비별로 생성하고, 다운로드/실행 기록을 SQLite/Slack/Notion과 연결한다.
- **배움:** 사용자 편의성과 credential 보호 사이의 균형을 단계적으로 설계해야 한다.

---

## 6. 결과 및 배움 (Result & Lessons)

### **[결과: 업무 단위 보안 인프라로 확장]**

- AD, Keycloak, Nextcloud, Mail, Storage, Wazuh가 개별 서비스가 아니라 하나의 보안 운영 흐름으로 연결되었다.
- 신규 입사자 온보딩은 AD 계정 생성에서 끝나지 않고, 그룹 권한, SSO, storage, mail, Wazuh baseline 검증과 리포트까지 이어진다.
- `verify-and-report.sh`를 통해 전체 IT health를 주기적으로 검증하고 Markdown/SQLite/Slack/Notion으로 증적화할 수 있는 기반이 생겼다.
- Wazuh는 단순 dashboard가 아니라 AD/IAM/협업/메일 계층을 연결하는 보안 가시성 중심이 되었다.

### **[배움: 기업 IT 운영의 핵심은 연결성]**

이번 구축에서 가장 크게 배운 점은 보안 인프라의 핵심이 개별 솔루션 설치가 아니라 연결성이라는 것이다.

AD는 계정 저장소이고, Keycloak은 SSO이고, Nextcloud는 파일 서버이고, Wazuh는 SIEM이라고 따로 보면 단순한 구축 목록에 그친다. 하지만 AD 그룹이 Keycloak claim이 되고, 그 claim이 Nextcloud storage 접근 권한이 되며, 그 접근과 인증 로그가 Wazuh에 모이고, 다시 Ansible 검증과 Markdown 리포트로 남으면 실제 운영 가능한 보안 체계가 된다.

### **[배움: 자동화는 실행보다 증명이 중요하다]**

운영 자동화는 명령을 대신 실행하는 수준에서 끝나면 위험하다. 실제 IT 운영에서는 "무엇을 변경했는지", "검증이 통과했는지", "실패했다면 어디서 실패했는지", "누가 후속 조치를 해야 하는지"가 남아야 한다.

이번 프로젝트에서는 온보딩과 IT health workflow에 Markdown report, SQLite record, Slack/Notion publish 경로를 붙여 자동화의 결과가 증적으로 남도록 설계했다.

### **[배움: 보안 자동화에는 명확한 권한 경계가 필요하다]**

비밀번호를 수집하지 않는 Mail 앱 등록, credential을 포함하지 않는 AD Join package, read-only shadow mode의 AI defense는 모두 같은 원칙에서 출발한다.

```text
자동화는 강력해야 하지만,
비밀정보와 운영 변경 권한은 최소화되어야 한다.
```

이 기준을 세워야 자동화가 편의 기능이 아니라 신뢰할 수 있는 보안 운영 체계가 된다.

---

## 7. 향후 계획 (Next Steps)

- **Helpdesk scenario 문서화:** 메일 로그인 실패, SSO 실패, 부서 폴더 미노출, 권한 오류 같은 실제 사용자 요청을 read-only 진단 workflow로 정리
- **Notion 운영 페이지 템플릿화:** Runbook, Incident Review, Weekly IT Health, Employee Onboarding Report 형식 표준화
- **Wazuh custom detection 강화:** Nextcloud, Keycloak, Mail, AD, Storage별 positive/negative fixture와 custom rule test harness 구축
- **Offline Domain Join v2:** credential 입력 없는 장비별 AD Join package와 다운로드 감사 기록 연결
- **AI defense shadow evaluation:** redaction leakage 0건, duplicate rate, latency, unknown rate를 기준으로 운영 가능성 검증
- **Slack 알림 taxonomy 정리:** `success`, `partial`, `failed`, `attention_required` 상태와 메시지 포맷 통일

---

## 8. 한 줄 정리

이번 프로젝트는 홈서버에 여러 서비스를 설치한 기록이 아니라, 기업 IT 환경에서 필요한 신원 관리, 접근 제어, 협업 서비스, 메일, 보안 관제, 운영 증적을 하나의 흐름으로 연결해 본 보안 인프라 구축 프로젝트다.
