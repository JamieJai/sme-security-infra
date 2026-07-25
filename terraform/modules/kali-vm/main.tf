resource "proxmox_vm_qemu" "kali_vm" {
  name        = var.vm_name
  target_node = var.target_node
  vmid        = var.vm_id

  bios    = "seabios"
  machine = "q35"
  scsihw  = "virtio-scsi-pci"
  qemu_os = "l26"

  agent            = var.qemu_agent_enabled ? 1 : 0
  automatic_reboot = false
  skip_ipv6        = true
  tablet           = true

  bootdisk = "scsi0"
  boot     = var.installer_attached ? "order=ide2;scsi0" : "order=scsi0"

  cpu {
    cores   = var.cores
    sockets = 1
    type    = "host"
  }

  memory = var.memory

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
        cdrom {
          iso = var.installer_attached ? var.installer_iso : ""
        }
      }
    }
  }

  network {
    id       = 0
    model    = "virtio"
    bridge   = var.bridge
    firewall = true
  }

  tags = join(",", var.tags)

  lifecycle {
    ignore_changes = [
      boot,
      bootdisk,
    ]
  }
}
