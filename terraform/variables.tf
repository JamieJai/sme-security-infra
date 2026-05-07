variable "proxmox_api_token_id" {
  description = "Proxmox API Token ID"
  type        = string
  sensitive   = true
}

variable "proxmox_api_token_secret" {
  description = "Proxmox API Token Secret"
  type        = string
  sensitive   = true
}

variable "proxmox_node" {
  description = "Proxmox target node"
  type        = string
  default     = "pve01"
}

variable "ci_user" {
  description = "Cloud-init default user"
  type        = string
  default     = "sysadmin"
}

variable "ci_password" {
  description = "Cloud-init user password"
  type        = string
  sensitive   = true          # terraform출력중 마스킹처리
}

variable "ssh_public_key" {
  description = "SSH public key for cloud-init"
  type        = string
}
