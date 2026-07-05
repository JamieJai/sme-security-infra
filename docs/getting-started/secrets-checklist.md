# Secret 및 Bootstrap 체크리스트

이 문서는 `homelab-infra` 저장소를 새 운영 노드에서 사용할 때 Git에 저장하지 않고 별도로 준비해야 하는 값과 파일을 정리한다.

## Git에 저장하지 않는 파일

다음 파일은 `.gitignore` 대상이며 Git에 커밋하지 않는다.

```text
terraform/terraform.tfvars
terraform/*.tfstate
terraform/*.tfstate.*
terraform/.terraform/
terraform/.terraform.lock.hcl
ansible/.vault_pass
ansible/group_vars/*vault*.yml
ansible/host_vars/*.yml
*.pem
id_ed25519*
id_rsa*
```

주의: 현재 저장소에는 운영 편의를 위해 일부 vault 파일과 host_vars가 로컬에 존재할 수 있다. 새 환경에서는 이 파일들의 내용을 별도 secret 전달 경로로 복원해야 한다.

## Terraform 필수 secret

`terraform/terraform.tfvars`에 최소 다음 값이 필요하다.

```hcl
ci_user        = "sysadmin"
ci_password    = "CHANGE_ME"
ssh_public_key = "ssh-ed25519 ..."
pm_api_url     = "https://<proxmox-host>:8006/api2/json"

proxmox_api_token_id     = "root@pam!terraform"
proxmox_api_token_secret = "CHANGE_ME"
```

또한 `vms` map에는 VM 이름, VMID, Proxmox node, template, CPU/RAM/disk, bridge, IP, gateway가 들어간다. 기준 예시는 `terraform/terraform.tfvars.example`을 따른다.

## Ansible 필수 secret

다음 파일을 준비한다.

```text
ansible/.vault_pass
ansible/group_vars/vault.yml
ansible/group_vars/keycloak-bind-vault.yml
ansible/group_vars/wazuh-rbac-vault.yml
```

대표적으로 필요한 값:

```text
AD Administrator 또는 bind 계정 암호
Keycloak admin 또는 LDAP federation 관련 secret
Nextcloud OIDC client secret
Mail/LDAP 연동에 필요한 bind secret
Wazuh RBAC/admin/break-glass 관련 secret
```

실제 변수명은 각 vault 파일과 관련 playbook을 기준으로 유지한다. 새 환경으로 옮길 때는 vault 파일 자체를 복원하거나 같은 변수명을 가진 새 vault 파일을 만든다.

## SSH bootstrap

컨트롤 노드에는 Ansible 접속용 SSH key가 필요하다.

기본 `ansible/ansible.cfg` 기준:

```text
~/.ssh/id_ed25519_homelab
```

대상 VM에는 `terraform.tfvars`의 `ssh_public_key`가 cloud-init으로 들어가야 한다.

## 새 운영 노드 준비 순서

1. Git clone

```bash
git clone <repo-url> /home/sysadmin/homelab-infra
cd /home/sysadmin/homelab-infra
```

2. 로컬 secret 복원

```bash
cp <secure-source>/terraform.tfvars terraform/terraform.tfvars
cp <secure-source>/.vault_pass ansible/.vault_pass
cp <secure-source>/*vault*.yml ansible/group_vars/
```

3. SSH key 준비

```bash
install -m 600 <secure-source>/id_ed25519_homelab ~/.ssh/id_ed25519_homelab
```

4. 비파괴 검증

```bash
./scripts/full-check.sh
```

5. 실제 적용

```bash
./scripts/full-apply.sh
```

`full-apply.sh`는 각 단계에서 `APPLY` 입력을 요구한다. 자동 승인 모드는 다음처럼 명시적으로만 사용한다.

```bash
AUTO_APPROVE=true ./scripts/full-apply.sh
```

Wazuh agent 설치/재배포까지 포함하려면 별도 옵션을 사용한다.

```bash
RUN_AGENT_DEPLOY=true ./scripts/full-apply.sh
```

## 복원 가능성 기준

새 환경에서 다음이 통과하면 Git + secret material 기반 재현성이 확보된 것으로 본다.

```bash
./scripts/terraform-plan.sh
./scripts/ansible-baseline.sh
./scripts/ansible-services.sh
./scripts/verify-all.sh
```

최종 통합 검증은 다음 명령으로 한다.

```bash
./scripts/full-check.sh
```
