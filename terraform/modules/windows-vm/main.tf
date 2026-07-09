resource "proxmox_vm_qemu" "windows_vm" {
  name        = var.vm_name
  target_node = var.target_node
  vmid        = var.vm_id

  bios    = "ovmf"
  machine = "q35"
  scsihw  = "virtio-scsi-pci"
  qemu_os = "win11"

  agent  = 1
  tablet = true

  bootdisk = "scsi0"
  boot     = "order=ide2;ide3;scsi0"

  cpu {
    cores   = var.cores
    sockets = 1
    type    = "host"
  }

  memory = var.memory

  efidisk {
    storage           = var.efi_storage
    efitype           = "4m"
    pre_enrolled_keys = true
  }

  tpm_state {
    storage = var.tpm_storage
    version = "v2.0"
  }

  disks {
    scsi {
      scsi0 {
        disk {
          size    = var.disk_size
          storage = var.storage
          discard = true
          format  = "raw"
        }
      }
    }

    ide {
      ide2 {
        cdrom {
          iso = var.windows_iso
        }
      }

      ide3 {
        cdrom {
          iso = var.virtio_iso
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

  vga {
    type   = "std"
    memory = 64
  }

  tags = join(",", var.tags)

  lifecycle {
    ignore_changes = [
      boot,
    ]
  }
}
