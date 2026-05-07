resource "proxmox_vm_qemu" "dc01" {
  name        = "dc01"
  target_node = var.proxmox_node
  clone       = "temp-fix-template"
  full_clone  = true

  bios    = "seabios"
  machine = "q35"
  scsihw  = "virtio-scsi-pci"

  cores   = 2
  sockets = 1
  memory  = 4096

  os_type = "cloud-init"
  agent   = 1
  boot    = "order=scsi0;ide2"   # cloud-init drive도 boot order에 추가

  # ==================== Disks ====================
  disks {
    # 메인 OS 디스크 (SCSI)
    scsi {
      scsi0 {
        disk {
          size    = "70G"
          storage = "local-lvm"
          discard = true
        }
      }
    }

    # Cloud-Init Drive (IDE2)
    ide {
      ide2 {
        cloudinit {
          storage = "local-lvm"
        }
      }
    }
  }

  # ==================== Network ====================
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  ipconfig0 = "ip=192.168.0.20/24,gw=192.168.0.1"

  ciuser    = var.ci_user
  cipassword = var.ci_password

  sshkeys = var.ssh_public_key
}
