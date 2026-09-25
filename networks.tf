# Three-tier network topology — see ../wm-infra-netlab/docs/decisions/0001-network-segmentation.md
#
# public-net  — NAT'd to the host's real internet connection. The router VM's
#               internet-facing NIC lives here. Nothing else should.
# private-net — isolated (no direct route out). App tier. Only reachable
#               via the router VM routing between public-net and private-net.
# data-net    — isolated (no direct route out). DB tier. Only reachable via
#               the router VM routing between private-net and data-net.
#
# DHCP is disabled on all three: every VM gets a static IP via cloud-init,
# so there's nothing to configure after first boot (same approach as the
# existing vault VM).

resource "libvirt_network" "public" {
  name      = "wm-netlab-public"
  mode      = "nat"
  domain    = "public.netlab.local"
  addresses = ["10.0.1.0/24"]
  autostart = true

  dhcp {
    enabled = false
  }

  dns {
    enabled = false
  }
}

resource "libvirt_network" "private" {
  name      = "wm-netlab-private"
  mode      = "none" # isolated — no route out except via the router VM
  domain    = "private.netlab.local"
  addresses = ["10.0.2.0/24"]
  autostart = true

  dhcp {
    enabled = false
  }

  dns {
    enabled = false
  }
}

resource "libvirt_network" "data" {
  name      = "wm-netlab-data"
  mode      = "none" # isolated — no route out except via the router VM
  domain    = "data.netlab.local"
  addresses = ["10.0.3.0/24"]
  autostart = true

  dhcp {
    enabled = false
  }

  dns {
    enabled = false
  }
}
