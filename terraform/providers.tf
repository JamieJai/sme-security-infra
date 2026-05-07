terraform {
  required_providers {
    proxmox = {
      source = "Telmate/proxmox"
      version = "3.0.2-rc04"
    }
  }
}

provider "proxmox" {
  pm_api_url = "https://192.168.0.200:8006/api2/json"

  pm_api_token_id = "root@pam!terraform"
  pm_api_token_secret = "43c790e5-db6b-4c99-bb44-445e172237b8"

  pm_tls_insecure = true
}
