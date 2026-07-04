variable "vm_name" { type = string }
variable "vm_id" { type = number }
variable "target_node" { type = string }
variable "template_name" { type = string }
variable "cores" { type = number }
variable "memory" { type = number }
variable "disk_size" { type = string }
variable "storage" { type = string }
variable "bridge" { type = string }
variable "ip_address" { type = string }
variable "gateway" { type = string }
variable "ci_user" { type = string }

variable "ci_password" {
  type      = string
  sensitive = true
}

variable "ssh_public_key" { type = string }

variable "tags" {
  type    = list(string)
  default = ["terraform"]
}
