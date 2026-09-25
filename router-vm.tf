# Fixed MAC addresses so cloud-init's network-config can reliably match
# each NIC by MAC, regardless of what order the kernel enumerates them in.
# 52:54:00 is the QEMU/KVM locally-administered OUI — same prefix already
# used by the existing infra-lab/vault networks.
locals {
  mac_public  = "52:54:00:ab:00:01"
  mac_private = "52:54:00:ab:00:02"
  mac_data    = "52:54:00:ab:00:03"
}

# The Ubuntu 24.04 cloud image, imported once as a libvirt volume.
resource "libvirt_volume" "ubuntu_base" {
  name   = "wm-netlab-ubuntu-24.04-base"
  pool   = var.storage_pool
  source = var.base_image_path
  format = "qcow2"
}

# The router's actual disk — a copy-on-write clone backed by the base
# image, so it doesn't duplicate the full image on disk.
resource "libvirt_volume" "router_disk" {
  name           = "wm-netlab-router.qcow2"
  pool           = var.storage_pool
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "router" {
  name = "wm-netlab-router-cloudinit.iso"
  pool = var.storage_pool

  user_data = templatefile("${path.module}/cloud-init/user-data.yaml.tftpl", {
    ssh_public_key = var.ssh_public_key
  })

  network_config = templatefile("${path.module}/cloud-init/network-config.yaml.tftpl", {
    mac_public  = local.mac_public
    mac_private = local.mac_private
    mac_data    = local.mac_data
  })
}

resource "libvirt_domain" "router" {
  name   = "wm-netlab-router"
  vcpu   = var.router_vcpu
  memory = var.router_memory_mb

  cloudinit = libvirt_cloudinit_disk.router.id

  disk {
    volume_id = libvirt_volume.router_disk.id
  }

  # Order matters only for humans reading this — cloud-init matches by MAC,
  # not position, so these can't get silently swapped by boot-order luck.
  network_interface {
    network_id     = libvirt_network.public.id
    mac            = local.mac_public
    wait_for_lease = false
  }

  network_interface {
    network_id     = libvirt_network.private.id
    mac            = local.mac_private
    wait_for_lease = false
  }

  network_interface {
    network_id     = libvirt_network.data.id
    mac            = local.mac_data
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  autostart = true
}

output "router_public_ip" {
  value = "10.0.1.10"
}

output "router_ssh_command" {
  value = "ssh netlab-admin@10.0.1.10"
}
