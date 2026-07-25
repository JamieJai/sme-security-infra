variable "vm_name" { type = string }
variable "vm_id" { type = number }
variable "target_node" { type = string }
variable "cores" { type = number }
variable "memory" { type = number }
variable "disk_size" { type = string }
variable "storage" { type = string }
variable "bridge" { type = string }
variable "installer_iso" { type = string }
variable "installer_attached" {
  type    = bool
  default = true
}
variable "qemu_agent_enabled" {
  type    = bool
  default = false
}
variable "tags" {
  type    = list(string)
  default = []
}
