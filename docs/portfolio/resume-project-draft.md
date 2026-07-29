# IT Manager Resume Project Draft

아래 문안은 이력서 프로젝트 경력란에 사용하는 압축본이다. 기간과 저장소 URL만
실제 값으로 바꾼다. 개인 homelab 프로젝트라는 표시는 삭제하지 않는다.

## 이력서용 압축본

### 기업형 IT 운영 자동화 플랫폼 구축

- **유형·기간:** 개인 프로젝트 | `[YYYY.MM - 현재]`
- **역할:** 인프라 설계, 구축, 운영 자동화 및 장애 대응 전 과정 수행
- **Repository:** `[GitHub URL]`

**기술:** Windows 11, Samba AD, Keycloak, Nextcloud, Wazuh, Proxmox,
Ansible, Terraform, PowerShell, Bash, SQLite

- Samba AD 계정과 부서 그룹 생성부터 Keycloak SSO, Nextcloud 권한, Mail,
  Wazuh baseline 검증까지 연결한 입사자 온보딩 workflow를 구현했습니다.
- 계정 삭제 없이 AD disable, 부서 그룹 회수, Keycloak session revoke, 자산
  회수 대기 상태를 기록하는 오프보딩 workflow를 구현하고 fixture로 safety
  gate를 검증했습니다.
- 사용자에게 관리자 암호를 제공하지 않고 승인 앱을 설치하도록 컴퓨터 계정 전용
  SMB share와 SYSTEM scheduled task를 설계하고 Windows pilot에서 실제 설치와
  reboot 후 실행까지 검증했습니다.
- Windows EventChannel 수집 장애와 Wazuh receiver 장애를 진단·복구하고,
  TCP 1514 및 8개 managed agent의 Active 복귀를 배포 성공 조건으로
  자동화했습니다.
- Ansible 반복 적용, Terraform plan, Markdown report, SQLite operation record,
  secret scan을 통해 변경 결과와 운영 증적을 관리했습니다.

## 상세 프로젝트 소개용

사내 IT Manager의 계정·권한, endpoint, 협업 도구, 사용자 지원, 보안 로그
업무를 개인 Proxmox homelab에서 하나의 workflow로 구현했습니다. 단순 서비스
설치보다 사용자가 업무를 시작할 수 있는 상태의 검증, 최소 권한, 반복 실행
수렴, 실패 기록과 재발 방지를 완료 기준으로 두었습니다.

### 입사자 온보딩

- AD 사용자, mail attribute, 부서 그룹 생성을 표준화했습니다.
- Keycloak LDAP federation, Nextcloud group/storage, Mail, Wazuh baseline을
  온보딩 후 자동 검증합니다.
- 비밀번호를 command argument나 report에 남기지 않습니다.
- 결과를 `success`, `partial`, `failed`로 구분해 Markdown과 SQLite에 기록합니다.

### Windows 앱 배포

- 사용자 share와 컴퓨터 installer share를 분리해 접근 주체별 권한을
  최소화했습니다.
- 일반 사용자의 권한을 높이지 않고 SYSTEM context에서 승인 앱만 설치합니다.
- pilot security group으로 범위를 제한하고 실제 설치, detection, 즉시 실행,
  reboot 후 ONSTART 실행을 검증했습니다.

### 퇴사자 오프보딩

- 변경 없는 plan과 승인된 execute 경로를 분리했습니다.
- AD 계정 disable, 관리 대상 그룹 회수, Keycloak session revoke와 Nextcloud
  user disable을 하나의 workflow로 연결했습니다.
- 지급 자산의 기존 상태와 owner를 보존하면서 `recovery_pending`으로 전환하도록
  설계했습니다.
- fixture에서 plan의 비변경성, 보호 계정 차단, 승인 gate를 검증했으며 live
  적용 경험으로 표현하지 않습니다.

### Wazuh 장애 대응

- JSON fixture와 live EventChannel decoder 차이로 custom rule이 누락된 원인을
  분석했습니다.
- Windows에서 처리할 수 없는 shared backup filename을 sync directory 밖으로
  분리했습니다.
- manager 상위 service가 active여도 receiver가 종료될 수 있는 문제를 확인하고,
  TCP 1514와 전체 agent Active를 post-deploy gate로 추가했습니다.

## 사용하지 않을 표현

- 실제 임직원 온보딩을 운영했다.
- production endpoint 8대를 관리했다.
- 대규모 SIEM 또는 SOC를 운영했다.
- macOS, Google Workspace, NAC/DLP를 운영했다.
- 실제 보안 사고 또는 악성코드를 대응했다.

대신 `개인 lab에서 구현·검증`, `test identity`, `Windows pilot`,
`managed Wazuh agent`처럼 검증 범위를 정확하게 표현한다.
