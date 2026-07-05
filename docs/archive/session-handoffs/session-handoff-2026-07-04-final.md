# Session Handoff - 2026-07-04 Final

이 문서는 오늘 처리한 인프라 작업과 다음 세션의 우선순위를 간단히 정리한 최신 인계본이다.

## 오늘 완료한 작업

- `verify-all.yml`을 기준으로 전체 인프라를 재검증했고 최종적으로 `failed=0`, `unreachable=0`을 확인했다.
- Terraform `plan -input=false`를 기준으로 drift 없이 정리했다.
- Proxmox Terraform 인증값(`proxmox_api_token_secret`, `ci_password`)의 placeholder 문제를 로컬 비추적 `terraform.tfvars` 기준으로 복구했다.
- `windows-test`로 남아 있던 VMID 105를 `keycloak` 기준으로 정리했다.
- Telmate Proxmox provider의 반복 `bootdisk` diff는 `terraform/modules/ubuntu-vm/main.tf`에서 `lifecycle.ignore_changes`로 정리했다.
- Wazuh AI shadow collector에 metrics/report를 추가했고, `redaction_leak_count=0`, loss indicators 0, pending 0 상태를 확인했다.
- `mail01`, `nextcloud`, `keycloak`, `wazuh`, `dc01`, `dc02`, `storage01`의 core host 매핑을 `/etc/hosts`와 Samba AD DNS 양쪽에서 정리했다.

## 추가한 검증

- AD DNS core A record 검증을 `verify-all.yml`에 포함했다.
- `dc01.toss.lan`, `dc02.toss.lan`, `wazuh.toss.lan`, `automation01.toss.lan`, `nextcloud.toss.lan`, `keycloak.toss.lan`, `storage01.toss.lan`, `mail01.toss.lan`이 Samba AD DNS에서 해석되는 것을 확인했다.
- Nextcloud에서 `mail01.toss.lan:25`, `:587`, `:993` 연결을 검증했다.
- 전체 관리 호스트에 Wazuh agent가 active인지 재확인했다.

## 현재 운영 상태

- Terraform: clean
- Ansible baseline: clean
- Wazuh snapshot/restore/timer/retention: verify 통과
- Wazuh AI shadow: metrics/report 생성 가능, shadow mode 유지
- Nextcloud mail/addressbook: 동작
- Samba AD DNS: core records 관리 시작

## 다음 우선 작업

1. AD DNS를 더 확장할지 결정한다.
   - 지금은 core host A record만 관리 중이다.
   - 필요하면 CNAME, PTR, 그리고 새 호스트 온보딩까지 IaC로 묶는다.
2. Wazuh AI shadow metrics를 정기 report로 남긴다.
   - 현재 report는 생성되지만 추세 보관과 경보는 약하다.
3. 오래된 문서에서 완료된 항목을 정리한다.
   - `session-handoff-2026-07-04.md`
   - `wazuh-platform-hardening.md`
4. Nextcloud TLS와 AD secret 정리 여부를 결정한다.

## 바로 다시 실행할 명령

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible-playbook -i inventory/hosts playbooks/ad-dns-records.yml
ansible-playbook -i inventory/hosts playbooks/verify-all.yml
```

