module "vm" {
  source = "./modules/ubuntu-vm"

  for_each = var.vms

  vm_name        = each.value.name
  vm_id          = each.value.vmid
  target_node    = each.value.target_node
  template_name  = each.value.template
  cores          = each.value.cores
  memory         = each.value.memory
  disk_size      = each.value.disk_size
  storage        = each.value.storage
  bridge         = each.value.bridge
  ip_address     = each.value.ip
  gateway        = each.value.gateway
  ci_user        = var.ci_user
  ci_password    = var.ci_password
  ssh_public_key = var.ssh_public_key
  tags           = each.value.tags
}
