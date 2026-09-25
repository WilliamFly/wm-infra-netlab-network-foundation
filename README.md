# wm-infra-netlab-network-foundation

Phase 1 of [wm-infra-netlab](https://github.com/<your-username>/wm-infra-netlab):
the libvirt network layer. Terraform (libvirt provider) provisions the
3-tier network topology described in
[ADR 0001](https://github.com/<your-username>/wm-infra-netlab/blob/main/docs/decisions/0001-network-segmentation.md).

## Current step: networks + router VM (no routing behavior yet)

This provisions the three isolated libvirt networks plus a minimal Ubuntu
24.04 router VM with one NIC per network, static IPs via cloud-init, and
SSH access. It does **not** yet do any actual routing — no IP forwarding,
no nftables NAT rules. That's the next step, applied via the
`harden-baseline` Ansible role. Right now this step just proves: the VM
boots, each NIC gets the right static IP (matched by MAC, not boot order),
and you can SSH in.

| Network | Libvirt name | Subnet | Mode |
|---|---|---|---|
| public-net | `wm-netlab-public` | 10.0.1.0/24 | NAT (reaches real internet via host) |
| private-net | `wm-netlab-private` | 10.0.2.0/24 | isolated (`none`) |
| data-net | `wm-netlab-data` | 10.0.3.0/24 | isolated (`none`) |

DHCP is disabled on all three — every VM in this lab gets a static IP via
cloud-init, so nothing needs manual config after first boot.

## Prerequisites

- libvirt/KVM running (`libvirtd`, socket-activated is fine)
- Terraform >= 1.9
- `dmacvicar/libvirt` provider (pinned `>= 0.8.1, < 0.9` — 0.9.x is a
  schema-breaking rewrite)

## Usage

```bash
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars: set base_image_path and ssh_public_key

terraform init
terraform plan
terraform apply
```

## Router VM

| | |
|---|---|
| Hostname | `netlab-router` |
| Admin user | `netlab-admin` (SSH key only, password login disabled) |
| public-net IP | `10.0.1.10` |
| private-net IP | `10.0.2.1` (gateway for private-net) |
| data-net IP | `10.0.3.1` (gateway for data-net) |
| Specs | 1 vCPU / 1GB RAM |

## Verifying

```bash
virsh net-list --all
# wm-netlab-public/private/data should be active, autostart yes

virsh list --all
# wm-netlab-router should be running

ssh netlab-admin@10.0.1.10
```

Inside the VM, confirm all three NICs got their correct static IP:

```bash
ip -br addr
```

## Next step

IP forwarding + nftables NAT/routing rules, applied via the
`harden-baseline` Ansible role extended for router duty. Until that's
done, this VM can be SSH'd into but doesn't actually route traffic between
the tiers yet.
