# 인증서 만료 감시 Runbook

`ansible/playbooks/certificate-expiry-monitor.yml`은 dc01, dc02, keycloak에
일일 인증서 만료 검사를 배포한다.

감시 대상은 다음과 같다.

- dc01/dc02 Samba LDAPS server certificate
- dc01/dc02 Samba local CA certificate
- Keycloak HAProxy LDAP endpoint certificate

기본 검사는 매일 06:15에 실행되며 최대 30분 임의 지연을 적용한다. 만료까지
60일 이하이면 journal에 `WARNING`을 기록한다. 30일 이하, 이미 만료됨, 파일
누락 또는 X.509 파싱 실패는 `CRITICAL`을 기록하고 systemd service를 실패
상태로 만든다.

## 배포

```bash
cd ansible
ansible-playbook -i inventory/hosts playbooks/certificate-expiry-monitor.yml
```

## 운영 확인

```bash
sudo /usr/local/sbin/check-certificate-expiry
systemctl list-timers certificate-expiry-monitor.timer
systemctl status certificate-expiry-monitor.service
journalctl -u certificate-expiry-monitor.service
```

service 실패는 인증서를 자동 갱신하지 않는다. Samba 인증서와 CA는 각 DC마다
서로 다르며, 갱신 시 Keycloak과 mail01의 trust store 배포도 함께 검증해야
한다. Keycloak HAProxy endpoint 인증서를 갱신할 때는 HAProxy PEM, OS trust
store, Java truststore를 모두 갱신한 뒤 LDAP sync를 재검증한다.
