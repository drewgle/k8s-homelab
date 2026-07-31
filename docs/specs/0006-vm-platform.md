# 0006 — VM platform for Kubernetes nodes

**Status:** Accepted
**Serves goals:** Learning (Proxmox, k8s); repo organization
**Planned files:** `infrastructure/ansible/roles/proxmox_vm/`,
`playbooks/talos/01-provision-vms.yml`, `playbooks/remove-vms.yml`
**Superseded requirements:** VMP-04 → VMP-11; VMP-07 → VMP-12

## Context

The bridge between the Proxmox layer and the Kubernetes layer: a shared role
that turns inventory definitions into running VMs, used by the Talos
provisioning playbook.

Earlier drafts of this spec described a two-OS platform (Talos alongside
Flatcar); that goal was removed on 2026-07-31 and the repo is Talos-only. The
superseded requirement IDs below are tombstones — git history has their text.

## Requirements

- **VMP-01** VM provisioning goes through the shared `proxmox_vm` role —
  bridge setup (`tasks/bridge.yml`) and VM create/start (`tasks/create.yml`).
  OS-specific behavior is limited to ISO choice and extra
  [`qm create`](https://pve.proxmox.com/pve-docs/qm.1.html) args, so the role
  stays generic even with one consumer.
- **VMP-02** VM networking uses a VLAN-aware bridge (`vm_bridge_name`,
  default `vmbr1`) persisted in `/etc/network/interfaces` (managed block)
  and applied with `ifreload -a`; VM NICs are tagged with `vm_vlan_id`
  (default 100).
- **VMP-03** VMs are distributed round-robin across all `proxmox` inventory
  hosts; a `proxmox_node` hostvar pins a VM to a specific node. The install
  ISO MUST be present on every node (downloaded in the prepare play) so any
  placement works. Round-robin applies to **first provisioning only** — a
  re-provision MUST pin the Proxmox host the slot already used, because CSI
  volume topology is keyed to it (spec
  [0008](0008-kubernetes-storage.md)).
- **VMP-04** **Superseded by VMP-11 below** (per-stack `vm_id` ranges for the
  removed two-OS platform).
- **VMP-05** VM disks are created on `vm_storage` (default `local-lvm` —
  which is why BMP-06 mandates the ext4+LVM install).
- **VMP-06** VM creation and start are idempotent: an existing `vm_id` on
  the target node short-circuits creation; a running VM short-circuits
  start. Re-running a provision playbook is safe.
- **VMP-07** **Superseded by VMP-12 below** (the two-stack address
  coexistence invariant for the removed two-OS platform).
- **VMP-08** Teardown (`remove-vms.yml`) MUST work across all Proxmox nodes
  (each node removes the target VMs that exist locally), require interactive
  confirmation unless `-e force=true`, and destroy disks
  (`qm destroy --purge`).
- **VMP-09** Provisioning is only complete when each VM answers on the
  [Talos maintenance API](https://www.talos.dev/latest/learn-more/talos-network-connectivity/)
  on 50000/tcp.
- **VMP-10** VM hardware baseline: q35 machine type, host CPU, virtio-scsi
  with iothread, serial console (`--serial0 socket --vga serial0`), QEMU
  guest agent enabled, `--onboot 1`.
- **VMP-11** Supersedes VMP-04. Every Kubernetes node host in inventory MUST
  define a `vm_id` equal to the final octet of its `ansible_host` — one number
  identifies the VM, the address and the node, and it survives a re-provision
  unchanged.
- **VMP-12** Supersedes VMP-07. There is **one** cluster and **one** address
  plan on `192.168.100.0/24`: the control-plane VIP at `.200`, control planes
  `.201–.210`, workers `.211–.239`, and the MetalLB pool `.240–.250` (spec
  [0009](0009-platform-services.md)). One pod CIDR and one service CIDR for
  the cluster. Node addresses MUST be static and come from inventory, because
  they appear in `certSANs`.

## Interfaces

Consumes: `vm_bridge_name`, `vm_vlan_id`, `vm_storage`, `vm_gateway`,
`vm_subnet`, `vm_cidr_bits`, `vm_cp_*`/`vm_worker_*` sizing vars; per-host
`vm_id`, `ansible_host`, optional `proxmox_node`. Talos and Kubernetes
versions come from `infrastructure/linux/talos/versions.yaml`
([Renovate](https://docs.renovatebot.com/)-managed).

## Acceptance criteria

- [ ] After a provision run, `qm list` across the nodes shows the VMs spread
      round-robin (or pinned per `proxmox_node`).
- [ ] Re-running the provision playbook reports zero changes.
- [ ] All VMs reach their readiness port (VMP-09) within the playbook's
      timeout.
- [ ] A full cluster is 6 VMs with no address conflict, reachable on the single
      endpoint at `.200`.
- [ ] `remove-vms.yml` empties every Proxmox node of the cluster's VMs after
      confirmation (or `-e force=true`).
- [ ] Re-provisioning one node preserves its `vm_id`, address and Proxmox host
      (VMP-11, VMP-03).

## Known limitations

- Default sizing (3× 4GB control plane + 3× 8GB workers = 36GB of 48GB physical,
  12GB per 16GB host) exceeds one node, so the cluster only fits spread across
  three hosts. A fourth 8GB worker does not fit; 6GB workers or more RAM is the
  precondition. Round-robin placement is load distribution, not a
  scheduler; capacity math is the operator's job.
- An in-place node re-provision runs the cluster at N-1 workers for its
  duration, because there is no headroom for a temporary node on a host already
  carrying 12GB. The workload set therefore has to fit on two workers.
- Placement is index-based round-robin: changing the Proxmox node count
  changes where re-created VMs land (existing VMs are untouched; a duplicate
  `vm_id` on another node fails loudly at `qm create`).
- VM creation shells out to `qm` over SSH rather than using the
  [`community.general.proxmox_kvm`](https://docs.ansible.com/ansible/latest/collections/community/general/proxmox_kvm_module.html)
  API module — a deliberate tradeoff to avoid requiring Proxmox API tokens.
