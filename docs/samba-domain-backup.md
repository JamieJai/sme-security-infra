# Samba domain backup

`ansible/playbooks/samba-domain-backup.yml`은 `active_dc`에 검증된 Samba AD
domain backup을 구성한다. 기본 실행 시각은 매일 03:30이며 최대 15분의 임의
지연을 적용한다.

각 백업 세트에는 다음 파일이 포함된다.

- `samba-tool domain backup online`이 생성한 domain archive
- ACL, extended attribute, numeric owner를 보존한 `sysvol.tar.bz2`
- 원본과 추출본 비교에 사용하는 `sysvol.acls`, `sysvol.xattrs`
- 두 archive의 `SHA256SUMS`
- 생성 시각, source DC, Samba 버전과 검증 결과를 기록한 `MANIFEST`

백업은 root 전용 `0700` 디렉터리에 저장되고 파일 권한은 `0600`이다. 기본
경로는 `/var/backups/samba-domain`이며 30일이 지난 완료 백업은 삭제된다.

## 배포

```bash
cd ansible
ansible-playbook -i inventory/hosts playbooks/samba-domain-backup.yml
```

배포 후 timer와 최근 실행 결과를 확인한다.

```bash
systemctl list-timers samba-domain-backup.timer
systemctl status samba-domain-backup.service
journalctl -u samba-domain-backup.service
```

## 즉시 실행

```bash
sudo systemctl start samba-domain-backup.service
sudo systemctl status samba-domain-backup.service
```

스크립트는 live DB와 SYSVOL 검사 후 백업을 생성한다. 이어서 임시 격리
디렉터리에 새 DC 이름으로 domain archive를 restore하고 복원 DB를 검사한다.
SYSVOL archive도 별도 임시 경로에 추출해 metadata를 읽을 수 있는지 확인한다.
모든 검사와 SHA256 검증을 통과한 경우에만 staging 디렉터리를 완료 백업으로
원자적으로 전환한다.

이 검증은 Samba 프로세스를 시작하지 않으며 운영 DNS, DB, SYSVOL을 변경하지
않는다. 실제 재해 복구 시에는 기존 DC를 모두 중지한 뒤 별도 승인된 복구
절차에 따라 backup restore 결과를 새 DC로 기동해야 한다.

이 플레이북의 기본 저장소는 active DC의 로컬 디스크다. 호스트 또는 디스크
전체 장애에 대비하려면 생성된 완료 백업을 별도 접근 통제가 적용된 off-host
저장소로 복제해야 한다.
