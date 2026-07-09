variable "vm_name" { type = string }
variable "vm_id" { type = number }
variable "target_node" { type = string }
variable "cores" { type = number }
variable "memory" { type = number }
variable "disk_size" { type = string }
variable "storage" { type = string }
variable "bridge" { type = string }
variable "windows_iso" { type = string }
variable "virtio_iso" { type = string }
variable "efi_storage" { type = string }
variable "tpm_storage" { type = string }
variable "tags" {
  type    = list(string)
  default = []
}
