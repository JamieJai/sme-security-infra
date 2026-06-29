variable "ci_user" { type = string }
variable "ci_password" {
  type      = string
  sensitive = true
}
variable "ssh_public_key" { type = string }

variable "vms" {
  type = map(object({
    name        = string
    vmid        = number
    target_node = string
    template    = string
    cores       = number
    memory      = number
    disk_size   = string
    storage     = string
    bridge      = string
    ip          = string
    gateway     = string
    tags        = optional(list(string))
  }))
}

variable "proxmox_api_token_id" {
  type      = string
  sensitive = true
}

variable "proxmox_api_token_secret" {
  type      = string
  sensitive = true
}

variable "pm_api_url" {
  type = string
}
