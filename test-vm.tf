# Throwaway VM on private-net ONLY — no public-net NIC at all. Its whole
# purpose is proving the router's NAT/forwarding actually moves packets
# (config correctness was already confirmed via `ufw status verbose` /
# `iptables -t nat -L`, but 0 bytes on those counters means it's never
# actually been exercised by real traffic).
#
# Gated behind create_private_test_vm so it's trivial to remove once it's
# done its job: set the var back to false and `terraform apply`.

locals {
  mac_private_test = "52:54:00:ab:01:01"
}

resource "libvirt_volume" "private_test_disk" {
  count          = var.create_private_test_vm ? 1 : 0
  name           = "wm-netlab-private-test.qcow2"
  pool           = var.storage_pool
  base_volume_id = libvirt_volume.ubuntu_base.id
  format         = "qcow2"
}

resource "libvirt_cloudinit_disk" "private_test" {
  count = var.create_private_test_vm ? 1 : 0
  name  = "wm-netlab-private-test-cloudinit.iso"
  pool  = var.storage_pool

  user_data = templatefile("${path.module}/cloud-init/private-test-user-data.yaml.tftpl", {
    ssh_public_key = var.ssh_public_key
  })

  network_config = templatefile("${path.module}/cloud-init/private-test-network-config.yaml.tftpl", {
    mac_private = local.mac_private_test
  })
}

resource "libvirt_domain" "private_test" {
  count  = var.create_private_test_vm ? 1 : 0
  name   = "wm-netlab-private-test"
  vcpu   = 1
  memory = 512

  cloudinit = libvirt_cloudinit_disk.private_test[0].id

  disk {
    volume_id = libvirt_volume.private_test_disk[0].id
  }

  network_interface {
    network_id     = libvirt_network.private.id
    mac            = local.mac_private_test
    wait_for_lease = false
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  autostart = false # this is a throwaway — don't want it surviving a host reboot by accident
}

output "private_test_vm_ip" {
  value = var.create_private_test_vm ? "10.0.2.50 (only reachable via the router VM, e.g. `ssh -J netlab-admin@10.0.1.10 netlab-admin@10.0.2.50`)" : "not created (create_private_test_vm = false)"
}
