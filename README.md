# wm-infra-netlab-network-foundation

Phase 1 of [wm-infra-netlab](https://github.com/WilliamFly/wm-infra-netlab):
the libvirt network layer. Terraform (libvirt provider) provisions the
3-tier network topology described in
[ADR 0001](https://github.com/WilliamFly/wm-infra-netlab/blob/main/docs/decisions/0001-network-segmentation.md).

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
| private-net IP | `10.0.2.254` (gateway for private-net) |
| data-net IP | `10.0.3.254` (gateway for data-net) |
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

## Status

Networking, NAT, and inter-tier routing are all live and verified — see
"Verifying routing works" below for how that was proven with real
traffic. Nothing here is still pending from the original build.

## Router configuration (Ansible)

`ansible/` contains one role local to this repo, plus one pulled in from
elsewhere:
- **`harden-baseline`** — reusable host hardening (SSH, users, base ufw
  policy, fail2ban, unattended-upgrades). Lives in its own repo,
  [wm-infra-netlab-harden-baseline](https://github.com/WilliamFly/wm-infra-netlab-harden-baseline),
  and is pulled in via `ansible-galaxy` (below) — not copied into this
  repo, so there's one canonical source shared across every project that
  needs it.
- **`router`** (in this repo, `ansible/roles/router/`) — depends on
  `harden-baseline` (see its `meta/main.yml`), adds IP forwarding, NAT
  masquerade, and `ufw route` rules controlling exactly which tiers can
  forward traffic to which.

Uses **ufw's routing support** (`ufw route allow`, NAT via
`/etc/ufw/before.rules`) rather than raw nftables — consistent with
`harden-baseline` already standardizing on ufw; running two firewall
tools on one box would conflict, since ufw itself sits on top of
iptables/nftables.

```bash
cd ansible
ansible-galaxy install -r requirements.yml
# ^ this one command fetches BOTH the harden-baseline role (into
#   roles/harden-baseline/, gitignored — always fetched fresh) AND the
#   community.general / ansible.posix collections the roles need.
ansible-playbook playbook-router.yml
```

**What the router role actually does:**
- Enables `net.ipv4.ip_forward` persistently
- Sets ufw's default forward policy to `DROP`
- Adds NAT masquerade so `private-net`/`data-net` traffic exits via
  `public-net` looking like it came from the router
- Allows forwarding `private-net → public-net` (internet access) and
  `private-net → data-net` (app reaching db)
- **No** rule allows `data-net` or `public-net` as a forwarding source —
  the default-DROP policy blocks those automatically, which is what
  actually enforces ADR 0001's isolation guarantee

## Verifying routing works

`ufw status verbose` / `iptables -t nat -L` confirm the *rules* are
correct, but 0 packets through them proves nothing was ever actually
routed. `test-vm.tf` provisions a throwaway VM on `private-net` only (no
public-net NIC) to generate real traffic through the router and prove it.

```bash
# terraform.tfvars: set
create_private_test_vm = true

terraform apply
```

SSH to it **through the router** (it has no direct path from your host
otherwise — this is a private-net-only VM, no public IP):
```bash
ssh -J netlab-admin@10.0.1.10 netlab-admin@10.0.2.50
```

From inside the test VM:
```bash
ping -c3 8.8.8.8               # raw IP connectivity through NAT
curl -sI https://example.com   # full outbound HTTPS through NAT
```

Both working confirms the router is actually forwarding and NAT-ing
`private-net` traffic out through `public-net` — not just holding
correct-but-unexercised firewall rules.

Back on the router, `sudo iptables -t nat -L POSTROUTING -n -v` should
now show non-zero packet/byte counts on the `10.0.2.0/24` MASQUERADE rule.

Note: your host machine can always reach `private-net`/`data-net`
directly (libvirt creates the network bridge on the host itself,
regardless of the network's isolation mode) — that's not a gap in the
isolation, it's just how the hypervisor works. What the isolation
actually guarantees is that nothing on `public-net` or the open internet
can reach `private-net`/`data-net` without an explicit `ufw route allow`
rule permitting it — which `ufw status verbose` already confirmed.

**Tear down once confirmed:**
```bash
# terraform.tfvars: set back to
create_private_test_vm = false

terraform apply
```

## Provisioning isolated-tier VMs (data-net)

`data-net` has no route to the internet by design (ADR 0001) — which
means anything on it (e.g. `wm-infra-netlab-db`) can't live-install
packages via cloud-init on first boot. The router role includes a
toggle for exactly this situation:

```bash
# temporarily open data-net -> internet
ansible-playbook playbook-router.yml -e router_temp_allow_data_egress=true

# ...finish provisioning the data-net VM by hand...

# close it again — always run this after
ansible-playbook playbook-router.yml -e router_temp_allow_data_egress=false
```

Both directions are idempotent — the rule is guaranteed present when
`true` and guaranteed absent when `false`. See
[ADR 0005](https://github.com/WilliamFly/wm-infra-netlab/blob/main/docs/decisions/0005-isolated-tier-provisioning.md)
for the full reasoning and the planned real fix (Packer-baked images,
which would remove the need for this toggle entirely).
