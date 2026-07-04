# Terraform Runbook

Terraform은 `sme-security-infra`의 VM 초기 생성과 기본 Proxmox 자원 구성을 담당한다. 서비스 구성은 Ansible이 담당한다.

## 디렉터리 기준

```text
terraform/
├── provider.tf
├── variables.tf
├── main.tf
├── terraform.tfvars.example
└── modules/ubuntu-vm/
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
