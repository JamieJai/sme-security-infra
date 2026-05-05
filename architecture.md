# SME Endpoint Security Infrastructure

---

## 1. Project Overview

본 프로젝트는 중소기업(SME) 환경에서
오픈소스 기반으로 Endpoint 중심 보안 인프라를 구축하는 것을 목표로 한다.

주요 목표는 다음과 같다.

- Active Directory 기반 계정 및 권한 관리
- Endpoint 보안 모니터링 및 위협 탐지
- 신규 입사자 Onboarding 자동화
- 퇴사자 Offboarding 자동화
- 내부 문서 접근 통제 및 파일 관리
- Incident Response 체계 구축
- 백업 및 장애 복구 자동화

---

## 2. Domain Information

Domain Name:
toss.lan

DNS Server:
192.168.0.20

NTP Server:
192.168.0.20

---

## 3. Infrastructure Design

| Server | IP | Role |
|---|---|---|
| AD Server | 192.168.0.20 | Samba AD + DNS + Chrony |
| Wazuh Server | 192.168.0.30 | Wazuh Manager + Dashboard |
| Automation Server | 192.168.0.40 | Terraform + Ansible + Git |
| Nextcloud Server | 192.168.0.50 | ECM + File Access Control |

---

## 4. OU Structure

OU=HR
OU=Finance
OU=Security
OU=IT
OU=Users
OU=Computers

---

## 5. Security Policies

### Password Policy

- 최소 10자 이상
- 대문자 + 소문자 + 숫자 + 특수문자 포함
- 90일 주기 변경
- 최근 5개 비밀번호 재사용 금지

### Account Lockout Policy

- 로그인 실패 5회 → 계정 잠금
- 30분 후 자동 해제

### USB Policy

- 미승인 USB 사용 제한
- Wazuh + osquery 기반 탐지

### BitLocker Policy

- 전사 기본 활성화
- 복구키 AD 저장

### Z Drive Policy

- 사용자별 네트워크 드라이브 자동 매핑
- 부서별 접근 권한 분리

### Offboarding Policy

- 계정 즉시 비활성화
- 그룹 제거
- 세션 강제 종료
- 자산 회수 확인

---

## 6. Backup Strategy

- Proxmox Snapshot Daily
- Samba AD Backup Daily
- Wazuh Snapshot Weekly
- Nextcloud Backup Daily

---

## 7. Disaster Recovery

- 주요 서버 장애 발생 시
Terraform + Ansible 기반 재배포

- AD 장애 발생 시
Samba Backup 기반 복구

---

## 8. Future Improvements

- TheHive + MISP 연동
- GitOps 기반 자동 배포
- Vault 기반 Secret 관리
- Security Onion 연동