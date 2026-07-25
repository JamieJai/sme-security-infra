# Terraform 운영 Runbook

Terraform은 `sme-security-infra`의 VM 초기 생성과 기본 Proxmox 자원 구성을 담당한다. 서비스 구성은 Ansible이 담당한다.

## 디렉터리 기준

```text
terraform/
├── provider.tf
├── variables.tf
├── main.tf
├── terraform.tfvars.example
└── modules/
    ├── kali-vm/
    ├── ubuntu-vm/
    └── windows-vm/
```

`terraform/`은 루트 `homelab-infra` Git 저장소에서 직접 관리한다. 별도 중첩 Git 저장소를 만들지 않는다. 과거에 잘못 생성되어 있던 `terraform/.git`은 제거했다.

## 민감 파일

다음 파일은 Git에 저장하지 않는다.

```text
terraform/terraform.tfvars
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/.terraform/
terraform/.terraform.lock.hcl
```

현재 로컬 민감 파일 권한 기준은 `600`이다.

## 실행 순서

```bash
cd /home/sysadmin/homelab-infra/terraform
terraform init
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Terraform apply 이후에는 Ansible inventory의 IP와 실제 VM IP가 맞는지 확인한다.

```bash
cd /home/sysadmin/homelab-infra/ansible
ansible all -m ping
```

## 현재 주의 사항

`terraform/modules/ubuntu-vm` 아래 파일이 `root:root` 소유라 일반 사용자로 `terraform fmt -recursive`를 완료할 수 없다. 현재 `terraform validate`는 통과하지만, fmt 정리를 위해 한 번 다음 조치가 필요하다.

```bash
sudo chown -R sysadmin:sysadmin /home/sysadmin/homelab-infra/terraform/modules/ubuntu-vm
cd /home/sysadmin/homelab-infra/terraform
terraform fmt -recursive
terraform validate
```

남은 fmt 차이는 공백 정렬 수준이다. 기능적인 validate 오류는 없다.

## Terraform과 Ansible 책임 분리

| 도구 | 책임 |
|---|---|
| Terraform | VM, CPU, RAM, disk, network, cloud-init 기본값 |
| Ansible | OS 설정, AD, Keycloak, Nextcloud, Mail, Wazuh, 보안 정책 |

Terraform은 서버를 만들고, Ansible은 서버를 서비스로 완성한다.

## Kali ISO VM

`kali_vms`는 scoped purple-team validation용 Kali 설치 VM을 만든다. ISO는 Terraform 실행 전에 Proxmox `local` ISO storage에 업로드되어 있어야 한다.

기본 기준:

- VM name: `kali01`
- VMID: `111`
- ISO: `local:iso/kali-linux-2026.2-installer-amd64.iso`
- Network: `vmbr0`, firewall enabled
- Resources: 2 vCPU, 4096 MiB RAM, 40G disk

설치 중에는 `installer_attached = true`, `qemu_agent_enabled = false`를 사용한다. 설치와 첫 부팅이 끝나면 ISO를 분리하고 Guest Agent 패키지를 설치한 뒤 값을 다음과 같이 전환한다.

```hcl
installer_attached = false
qemu_agent_enabled = true
```

Kali 모듈은 공급자가 실행 중 VM을 임의 재부팅하지 않도록 `automatic_reboot = false`를 사용한다. 재부팅이 필요한 변경은 운영자가 정상 종료 또는 재부팅으로 적용하고 서비스 복구를 확인한다. IPv4 전용 lab VM의 Guest Agent 조회 지연을 피하려고 `skip_ipv6 = true`를 사용한다.

Kali에서 검증 트래픽을 발생시키기 전에는 `docs/operations/kali-purple-team-validation.md`의 scope, stop condition, evidence 기준을 먼저 확인한다.

### Proxmox VNC Console Helper

`scripts/proxmox_vnc_console.py`는 API token으로 짧은 수명의 VNC ticket을 발급받아 VM console screenshot과 keyboard input을 수행한다. API token, VNC ticket, 입력 파일 내용은 출력하지 않는다.

필요 패키지는 저장소 밖의 임시 virtual environment에 설치한다.

```bash
python3 -m venv /tmp/proxmox-console-venv
/tmp/proxmox-console-venv/bin/pip install websocket-client pycryptodome pillow
```

예시:

```bash
/tmp/proxmox-console-venv/bin/python scripts/proxmox_vnc_console.py \
  --vmid 111 --output artifacts/kali-console/current.png screenshot

/tmp/proxmox-console-venv/bin/python scripts/proxmox_vnc_console.py \
  --vmid 111 chord Control Alt T

/tmp/proxmox-console-venv/bin/python scripts/proxmox_vnc_console.py \
  --vmid 111 type-file /path/to/restricted-input-file
```

`type-file`은 password 같은 값을 shell argument에 노출하지 않기 위한 입력 방식이다. 입력 파일은 Git에서 제외하고 최소 권한으로 보관한다. helper는 `PROXMOX_URL`, `PROXMOX_TOKEN_ID`, `PROXMOX_TOKEN_SECRET` 환경 변수 또는 로컬 `terraform/terraform.tfvars`를 사용한다.
