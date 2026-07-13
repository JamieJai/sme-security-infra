# [Project 08] Endpoint Onboarding 자동화 및 ODJ 기반 PC 배포 설계

*"온라인 AD Join 도구의 실무 경험을 바탕으로, 신규 PC 지급부터 도메인 가입, 필수 앱 설치, 검증, 운영 증적까지 이어지는 엔드포인트 온보딩 체계 설계"*

## 1. 개요 (Overview)

- **목표**: 신규 입사자 또는 교체 PC를 사내 업무 환경에 투입할 때, 도메인 가입과 기본 환경 설정을 수동 작업이 아니라 표준화된 IT 운영 workflow로 관리한다.
- **핵심 방향**: 기존 회사에서 사용했던 `act_ad.exe` 형태의 온라인 AD Join 도구 경험을 기준으로, homelab 환경에서는 `AD Join package -> ODJ -> 검증/증적` 구조로 고도화한다.
- **핵심 성과**:
  - 사번 기반 Windows AD Join package v1 구현
  - `win-mgmt01` 기반 Offline Domain Join blob 발급 자동화 설계
  - ODJ package 생성 및 SQLite operations record 기록 기반 마련
  - PC별 AD computer object lifecycle과 회수 절차 문서화
  - 향후 앱 설치, 네트워크 preflight, Wazuh endpoint visibility까지 연결 가능한 구조 정리

---

## 2. 문제 발견 (Problem Identification)

### **[현상]**

회사에서 PC를 지급받을 때 단순히 Windows만 설치되어 있다고 바로 업무를 시작할 수 있는 것은 아니다. 실제로는 사내망 연결, DNS/IP 설정, 필수 프로그램 설치, 도메인 가입, 계정 로그인, 권한 동기화 같은 여러 단계가 필요하다.

과거 회사에서는 `act_ad.exe` 같은 도구를 통해 이 과정을 어느 정도 자동화하고 있었다. 사용자는 온라인 상태에서 프로그램을 실행하고, 사번과 비밀번호를 입력하면 프로그램이 네트워크 상태를 확인한 뒤 도메인 가입과 후속 설정을 진행하는 방식이었다.

이 경험을 통해 PC 온보딩에서 중요한 것은 단순한 AD Join 명령이 아니라는 점을 체감했다.

```plain text
필수 앱 설치
  -> DNS/IP 설정
  -> AD 연결 확인
  -> 사용자 인증
  -> 도메인 가입
  -> 재부팅
  -> 업무 서비스 접근 확인
```

### **[임팩트]**

- **운영 표준화 문제**: PC마다 담당자가 수동으로 설정하면 DNS, PC명, 설치 앱, 도메인 가입 방식이 달라질 수 있다.
- **보안 리스크**: 도메인 join credential을 스크립트나 공유 폴더에 넣는 방식은 유출 위험이 크다.
- **사용자 경험 저하**: 신규 입사자가 처음 PC를 받았을 때 어떤 순서로 로그인하고 서비스를 확인해야 하는지 명확하지 않으면 IT 문의가 반복된다.
- **증적 부족**: 어떤 PC가 누구에게 지급됐고, 언제 도메인 가입 package가 발급됐으며, 실패 시 어떤 조치를 했는지 기록이 남지 않으면 운영 품질을 설명하기 어렵다.

---

## 3. 해결 과정 (Implementation)

### **[기술적 조치 1: AD Join package v1 구현]**

첫 단계에서는 가장 단순하고 안전한 방식으로 Windows AD Join self-service package를 만들었다.

- `scripts/generate-windows-ad-join-package.sh`를 통해 사번과 PC명을 기준으로 package 생성
- `Join-HomelabDomain.ps1`에서 DNS 설정, 도메인 resolution 확인, `Add-Computer` 실행
- package 내부에는 domain admin password, join account password, token을 포함하지 않음
- 사용자는 실행 시 `Get-Credential`을 통해 권한 있는 계정을 입력

이 방식은 완전 자동화는 아니지만, 비밀번호를 파일에 저장하지 않는다는 점에서 안전한 v1 fallback이다. 특히 초기 단계에서는 자동화 범위보다 credential 보호를 우선했다.

### **[기술적 조치 2: Offline Domain Join 기반 v2 설계]**

다음 단계로 검토한 방식이 Offline Domain Join이다. ODJ는 사용자별 로그인권이 아니라 PC별 사전 승인 자료에 가깝다.

```plain text
IT 관리 호스트
  -> djoin /provision
  -> PC 이름별 ODJ blob 생성
  -> AD computer object 생성

사용자 PC
  -> djoin /requestODJ
  -> ODJ blob 적용
  -> 재부팅
  -> 사내망/VPN 연결 후 AD 사용자 로그인
```

기존 온라인 AD Join 도구와의 차이는 명확하다.

- `act_ad.exe` 방식은 온라인 상태에서 사용자 인증을 받고, 현재 PC를 도메인에 가입시키는 onboarding agent에 가깝다.
- ODJ는 온라인 agent 전체를 대체하는 것이 아니라, 그 안에서 사용할 수 있는 도메인 가입 방식 중 하나다.
- ODJ blob은 사용자별이 아니라 computer name과 AD computer object에 묶인다.
- 따라서 같은 blob을 여러 PC에 복제하면 안 되고, PC별로 발급/배포/회수해야 한다.

### **[기술적 조치 3: Windows 관리 호스트와 자동화 경로 구성]**

Samba AD DC만으로는 Windows ODJ blob을 직접 생성하는 경로가 제한적이었다. 따라서 Windows Server를 새로 도입하기보다, 라이선스가 있는 Windows 11 관리 VM을 ODJ 전용 host로 두는 방향을 선택했다.

- `win-mgmt01`을 Windows management VM으로 구성
- RSAT/djoin 실행 환경 확인
- AD DNS와 DC discovery 검증
- `Administrator@toss.lan` 권한은 Ansible Vault에서만 사용
- SSH session에서 직접 credential을 노출하지 않고, 1회성 scheduled task를 통해 `djoin.exe /provision` 실행
- task와 임시 script 삭제 후 ODJ blob ACL을 `SYSTEM`과 `Administrators`로 제한

이 과정에서 중요한 판단은 ODJ 자동화도 결국 credential을 다루는 작업이라는 점이다. 그래서 실행 결과는 남기되, credential 값이나 blob 원문은 Git/Notion/log에 남기지 않는 기준을 세웠다.

### **[기술적 조치 4: Package 생성과 운영 증적 연결]**

ODJ blob은 단순 파일이 아니라 도메인 가입 권한을 내포한 민감 자료다. 따라서 package 생성 자체도 운영 기록으로 남겨야 한다.

- `scripts/generate-windows-odj-package.sh`
  - ODJ blob과 `Apply-OfflineDomainJoin.ps1`을 PC별 package로 묶음
  - package file permission을 제한
  - `.codex/mcp/homelab_ops.sqlite`에 `endpoint_odj_package` 기록 저장
- `endpoint/windows/offline-domain-join/Apply-OfflineDomainJoin.ps1`
  - 로컬 관리자 권한 확인
  - computer name 형식 확인
  - ODJ blob 존재 여부 확인
  - DNS 설정 후 `djoin /requestODJ` 적용

여기서 목표는 "실행파일 하나 만들기"가 아니라, 발급과 적용, 실패와 회수까지 운영자가 추적할 수 있는 구조를 만드는 것이다.

---

## 4. 보안 아키텍처 설계 (Current Architecture)

현재 endpoint onboarding 구조는 다음 역할로 나뉜다.

- **Identity**: Samba AD - 사용자, 그룹, computer object, DNS, Kerberos 기준점
- **Management Host**: `win-mgmt01` - RSAT/djoin 기반 ODJ blob 발급
- **Endpoint Package**: AD Join v1 package 또는 ODJ v2 package
- **Operations**: Ansible, shell script, PowerShell - 발급, 적용, 검증 자동화
- **Evidence**: SQLite operations DB, Markdown docs - 실행 결과와 운영 증적
- **Notification/Knowledge**: Slack, Notion - 운영 알림과 승인된 문서 보관
- **Security Visibility**: Wazuh - endpoint onboarding 단계에서 agent를 설치하고 인증/보안 이벤트를 관찰

목표 흐름은 다음과 같다.

```plain text
신규 PC 지급
  -> asset tag / employee_id / computer_name 매핑
  -> 필수 앱 설치 및 네트워크 preflight
  -> AD Join v1 또는 ODJ v2 package 적용
  -> Wazuh agent 설치 및 enrollment
  -> 재부팅
  -> AD 사용자 로그인
  -> Keycloak/Nextcloud/Mail 접근 확인
  -> Wazuh endpoint baseline 확인
  -> SQLite 기록
  -> Slack/Notion 운영 증적화
```

---

## 5. 트러블슈팅 및 설계 판단 (Trouble Shooting)

### **[온라인 AD Join 도구와 ODJ의 역할 분리]**

- **문제**: 처음에는 ODJ가 `act_ad.exe` 같은 온라인 AD Join 도구를 완전히 대체하는 개념처럼 보일 수 있었다.
- **분석**: 실제로는 `act_ad.exe`는 앱 설치, 네트워크 설정, 사용자 인증, 도메인 가입까지 묶은 onboarding agent이고, ODJ는 그중 도메인 가입을 처리하는 방식 중 하나다.
- **판단**: 최종 목표는 ODJ 단독 도구가 아니라, 온라인 preflight와 ODJ를 조합한 endpoint onboarding workflow로 잡았다.
- **배움**: 기술 하나를 기능으로만 보면 좁게 보이지만, 실제 운영 업무 안에 넣으면 역할과 경계가 명확해진다.

### **[ODJ blob을 공통 이미지에 넣지 않는 이유]**

- **문제**: 100대 PC를 사전 세팅할 때 하나의 ODJ blob을 이미지에 포함하면 편해 보일 수 있다.
- **위험**: ODJ blob은 특정 computer name과 AD computer object에 묶인다. 같은 blob을 여러 PC에 복제하면 computer identity 충돌과 보안 사고로 이어질 수 있다.
- **판단**: 공통 Windows image에는 필수 앱과 onboarding script만 포함하고, ODJ blob은 PC별로 별도 발급/전달하는 구조가 맞다.
- **배움**: 대량 배포에서 중요한 것은 하나의 이미지를 복제하는 속도보다, 각 장비의 identity를 구분하고 회수할 수 있는 체계다.

### **[실제 client 검증을 뒤로 미룬 이유]**

- **문제**: ODJ apply end-to-end 검증에는 workgroup 상태의 Windows client가 필요하다.
- **판단**: 리소스 절감을 위해 별도 Windows endpoint VM을 상시 유지하지 않고, 실제 노트북이 준비되면 검증하기로 했다.
- **현재 상태**: `win-mgmt01`에서 ODJ blob 발급과 package 생성은 검증됐고, 실제 client 적용 검증만 남아 있다.
- **배움**: 모든 검증 환경을 상시 유지하는 것이 항상 좋은 것은 아니며, 운영 비용과 검증 목적을 분리해야 한다.

---

## 6. 결과 및 배움 (Result & Lessons)

### **[결과: PC 도메인 가입을 운영 workflow로 확장]**

- Windows AD Join v1 package를 통해 credential을 파일에 넣지 않는 안전한 fallback을 마련했다.
- Windows management host 기반으로 ODJ blob을 발급할 수 있는 자동화 경로를 만들었다.
- ODJ package 생성 결과를 SQLite operations DB에 기록하여 운영 증적을 남길 수 있게 했다.
- endpoint onboarding 문서를 통해 발급, 적용, 실패, 회수 기준을 정리했다.

### **[배움: Endpoint 관리는 계정 관리와 자산 관리의 접점]**

PC 도메인 가입은 단순히 Windows를 AD에 붙이는 작업이 아니다. 어떤 장비가 어떤 이름으로 AD에 들어오고, 어떤 사용자에게 지급되며, 어떤 권한과 서비스에 접근하게 되는지를 연결하는 지점이다.

이 과정을 표준화하면 신규 입사자 온보딩, 자산 관리, 보안 로그, 장애 대응이 하나의 흐름으로 이어진다.

### **[배움: 자동화의 핵심은 편의성보다 회수 가능성]**

Endpoint onboarding에서 편의성만 보면 "한 번에 실행되는 파일"이 가장 좋아 보인다. 하지만 IT Manager 관점에서는 잘못 발급된 package를 회수할 수 있는지, 어떤 AD computer object를 disable/delete해야 하는지, 실패 기록이 남는지가 더 중요하다.

```plain text
빠르게 가입시키는 것보다
누가, 어떤 장비를, 어떤 근거로 가입시켰는지 설명할 수 있어야 한다.
```

---

## 7. 향후 계획 (Next Steps)

- **실물 Windows 노트북 검증**: ODJ package 적용, 재부팅, AD 로그인, DNS/SPN 상태 확인
- **온보딩 agent 확장**: 필수 앱 설치, DNS/IP 설정, 사내망 연결 확인, ODJ 적용을 하나의 flow로 묶기
- **자산 매핑 설계**: employee_id, asset tag, serial number, computer name, AD computer object를 operations DB에 연결
- **Helpdesk scenario 문서화**: PC 도메인 가입 실패, DNS 오류, AD 로그인 실패, 부서 권한 미노출 상황을 진단 절차로 정리
- **Wazuh 연동**: endpoint의 인증 이벤트와 보안 baseline을 IT health report에 포함
- **Notion/Slack 운영화**: package 발급, 적용 성공, 실패, 회수 결과를 운영 알림과 문서로 남기기

---

## 8. 한 줄 정리

이번 작업은 AD Join 실행파일을 만드는 것이 아니라, 신규 PC 지급과 도메인 가입을 자산 관리, 인증 보안, 운영 검증, 증적 관리까지 이어지는 Endpoint Onboarding workflow로 확장하는 과정이다.
