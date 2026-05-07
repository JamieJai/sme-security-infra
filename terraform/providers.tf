terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.70"  # 최신 버전대
    }
  }
}

provider "proxmox" {
  endpoint = "https://192.168.0.200:8006/api2/json"
  api_token = "${var.proxmox_api_token_id}:${var.proxmox_api_token_secret}"

  insecure = true
  # ssh_agent = true       # 나중에 SSH Agent 사용할 때
}
