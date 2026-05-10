resource "proxmox_vm_qemu" "ubuntu_vm" {
  name        = var.vm_name
  target_node = var.target_node
  vmid        = var.vm_id

  clone       = var.template_name
  full_clone  = true

  bios     = "seabios"
  machine  = "q35"
  scsihw   = "virtio-scsi-pci"

  # CPU
  cpu {
    cores   = var.cores
    sockets = 1
  }

  memory = var.memory

  os_type = "cloud-init"
  agent   = 1

  bootdisk = "scsi0"
  boot = "order=scsi0;ide2"

  # ==================== Disks ====================
  disks {
    scsi {
      scsi0 {
        disk {
          size    = var.disk_size
          storage = var.storage
          discard = true
        }
      }
    }

    ide {
      ide2 {
        cloudinit {
          storage = var.storage
        }
      }
    }
  }

  # ==================== Network ====================
  network {
    id     = 0
    model  = "virtio"
    bridge = var.bridge
  }

  ipconfig0 = "ip=${var.ip_address}/24,gw=${var.gateway}"

  ciuser     = var.ci_user
  cipassword = var.ci_password
  sshkeys    = var.ssh_public_key

  tags= join(",", var.tags)
}
