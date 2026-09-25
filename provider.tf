terraform {
  required_version = ">= 1.9"

  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = ">= 0.8.1, < 0.9" # 0.9.x is a schema-breaking rewrite — pinned to match infra-lab
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}
