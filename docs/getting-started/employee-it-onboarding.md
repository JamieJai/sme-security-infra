# Employee IT Onboarding Guide

이 문서는 신규 입사자가 처음 PC를 받고 사내 IT 서비스를 사용하는 순서를 설명한다.

## 1. Windows PC AD Join

IT팀에서 전달한 사번별 AD Join package를 다운로드한다.

예상 URL 형식:

```text
https://it-onboarding.example.local/endpoint/windows/ad-join?employee_id=<사번>
```

현재 v1에서는 실제 웹 포털 대신 IT팀이 생성한 package를 제한된 공유 경로로 전달한다.

실행 순서:

1. Windows에 로컬 관리자 계정으로 로그인한다.
2. DNS가 사내 AD DNS를 바라보는지 확인한다.
3. package 안의 `run-as-admin.cmd`를 관리자 권한으로 실행한다.
4. AD 계정 정보를 입력한다.
5. PC가 재부팅되면 도메인 계정으로 로그인한다.

주의:

- 스크립트 안에는 비밀번호가 들어 있지 않다.
- 비밀번호를 메신저나 캡처 화면으로 공유하지 않는다.
- DNS 확인에 실패하면 IT팀에 오류 화면과 현재 네트워크 정보를 전달한다.

## 2. SSO Login

AD Join 후 Keycloak 기반 SSO를 사용한다. 서비스별 접근은 부서 그룹에 따라 자동 부여된다.

## 3. Mail

Nextcloud Mail 또는 사내 메일 클라이언트에서 계정을 확인한다. 로그인 실패 시 다음 정보를 IT팀에 전달한다.

- 발생 시각
- 사용한 ID 형식
- 오류 메시지
- PC가 AD Join 후 재부팅됐는지 여부

## 4. Nextcloud

Nextcloud에서 개인 파일과 부서 공유 폴더를 확인한다. 부서 폴더가 보이지 않으면 계정 그룹 동기화 또는 OIDC group claim 문제일 수 있다.

## 5. Nextcloud Talk

사내 웹 메신저는 Nextcloud Talk를 사용한다. 브라우저에서 Nextcloud에 접속한 뒤 Talk 메뉴를 연다.

용도:

- IT 공지 확인
- 입사 초기 문의
- 부서 내 간단한 커뮤니케이션

운영 알림은 Slack으로, 사용자 간 커뮤니케이션은 Nextcloud Talk로 분리한다.
