# 0006 — VM platform for Kubernetes nodes

**Status:** Accepted
**Serves goals:** Learning (Proxmox, k8s); distro evaluation; repo organization
**Planned files:** `infrastructure/ansible/roles/proxmox_vm/`,
`playbooks/talos/01-provision-vms.yml`, `playbooks/flatcar/01-provision-vms.yml`,
`playbooks/remove-vms.yml`
**Amended by:** [0019](0019-single-cluster-mixed-distro.md)
**Superseded requirements:** VMP-04 → VMP-11; VMP-07 → VMP-12 and 0019 MIX-09

## Context

The bridge between the Proxmox layer and the Kubernetes layer: a shared role
that turns inventory definitions into running VMs, used identically by every
node distro's provisioning playbook so that swapping one node's distro (spec
[0019](0019-single-cluster-mixed-distro.md)) is a re-provision rather than a
rebuild, and the evaluation in spec [0010](0010-node-os-evaluation.md) has
something to measure.

An earlier draft of this spec described two isolated stacks that would coexist
by never sharing an address. Spec 0019 replaces that with one cluster whose
nodes each declare a distro; VMP-11 and VMP-12 below carry the change, and the
requirements they replace are kept in place for traceability.

## Requirements

- **VMP-01** Every node distro provisions through the shared `proxmox_vm` role —
  bridge setup (`tasks/bridge.yml`) and VM create/start (`tasks/create.yml`).
  Distro-specific behavior is limited to ISO choice,
  [cloud-init](https://cloudinit.readthedocs.io/)/[Ignition](https://coreos.github.io/ignition/)
  snippets, and extra
  [`qm create`](https://pve.proxmox.com/pve-docs/qm.1.html) args. Adding a distro
  MUST NOT change this role.
- **VMP-02** VM networking uses a VLAN-aware bridge (`vm_bridge_name`,
  default `vmbr1`) persisted in `/etc/network/interfaces` (managed block)
  and applied with `ifreload -a`; VM NICs are tagged with `vm_vlan_id`
  (default 100).
- **VMP-03** VMs are distributed round-robin across all `proxmox` inventory
  hosts; a `proxmox_node` hostvar pins a VM to a specific node. The install
  ISO MUST be present on every node (downloaded in the prepare play) so any
  placement works. Round-robin applies to **first provisioning only** — a
  re-provision MUST pin the Proxmox host the slot already used, because volume
  topology is keyed to it (0019 MIX-28).
- **VMP-04** **Superseded by VMP-11 below.** *Historical text: Every
  Kubernetes node host in inventory MUST define a cluster-unique `vm_id`. Talos
  uses 2xx, Flatcar 3xx.*
- **VMP-05** VM disks are created on `vm_storage` (default `local-lvm` —
  which is why BMP-06 mandates the ext4+LVM install).
- **VMP-06** VM creation and start are idempotent: an existing `vm_id` on
  the target node short-circuits creation; a running VM short-circuits
  start. Re-running a provision playbook is safe.
- **VMP-07** **Superseded by VMP-12 below and
  [0019 MIX-09](0019-single-cluster-mixed-distro.md).** *Historical text:
  Coexistence invariant: the two stacks MUST NOT collide on any address. Talos
  takes `192.168.100.201-213` with pod CIDR `10.244.0.0/16` and service CIDR
  `10.96.0.0/12`; Flatcar takes `192.168.100.221-233` with `10.245.0.0/16` and
  `10.112.0.0/12`. Both may therefore run at once, which is what makes the
  side-by-side comparison in spec 0010 possible; capacity, not addressing, is the
  limit. `remove-vms.yml -e vm_type=<talos|flatcar>` tears down one stack without
  touching the other.*
- **VMP-08** Teardown (`remove-vms.yml`) MUST work across all Proxmox nodes
  (each node removes the target VMs that exist locally), require interactive
  confirmation unless `-e force=true`, destroy disks (`qm destroy --purge`),
  and clean up cloud-init/ignition snippets.
- **VMP-09** Provisioning is only complete when each VM answers on its distro's
  readiness port, taken from that distro's `distro.yaml` (0019 MIX-18) rather
  than hard-coded per stack —
  [Talos maintenance API](https://www.talos.dev/latest/learn-more/talos-network-connectivity/)
  on 50000/tcp, Flatcar SSH on 22/tcp.
- **VMP-10** VM hardware baseline: q35 machine type, host CPU, virtio-scsi
  with iothread, serial console (`--serial0 socket --vga serial0`), QEMU
  guest agent enabled, `--onboot 1`.
- **VMP-11** Supersedes VMP-04. Every Kubernetes node host in inventory MUST
  define a `vm_id` equal to the final octet of its `ansible_host`, and it MUST
  NOT encode the distro — one number identifies the VM, the address and the node,
  and it survives a distro swap unchanged. See 0019 MIX-08 and MIX-10.
- **VMP-12** Supersedes VMP-07. There is **one** cluster and **one** address
  plan, defined authoritatively by 0019 MIX-09: control planes `.201–.210`,
  workers `.211–.239`, the single control-plane VIP at `.200`, and the MetalLB
  pool `.240–.250` (spec [0009](0009-platform-services.md)). One pod CIDR and one
  service CIDR for the cluster. Node addresses MUST be static and come from
  inventory, because they appear in `certSANs` (0019 MIX-11). Teardown selects by
  node — `remove-vms.yml -e nodes=[...]` or `-e teardown=true` for the whole
  cluster — and MUST NOT destroy a VM whose Kubernetes Node object still exists
  unless tearing the cluster down (0019 MIX-27).

## Interfaces

Consumes: `vm_bridge_name`, `vm_vlan_id`, `vm_storage`, `vm_gateway`,
`vm_subnet`, `vm_cidr_bits`, `vm_cp_*`/`vm_worker_*` sizing vars; per-host
`vm_id`, `ansible_host`, `node_distro`, optional `proxmox_node`. ISO versions come
from each distro's `infrastructure/linux/<distro>/versions.yaml`
([Renovate](https://docs.renovatebot.com/)-managed where a datasource
exists); the Kubernetes version itself is cluster-wide and lives in
`infrastructure/linux/cluster/versions.yaml` (0019 MIX-22).

## Acceptance criteria

- [ ] After a provision run, `qm list` across the nodes shows the VMs spread
      round-robin (or pinned per `proxmox_node`).
- [ ] Re-running the provision playbook reports zero changes.
- [ ] All VMs reach their readiness port (VMP-09) within the playbook's
      timeout.
- [ ] A full cluster is 6 VMs with no address conflict, reachable on the single
      endpoint at `.200`.
- [ ] `remove-vms.yml -e nodes=[...]` refuses to destroy a VM whose Kubernetes
      Node object still exists; `-e teardown=true` empties every Proxmox node of
      the cluster's VMs and the snippets directory of their configs.
- [ ] Re-provisioning one node with a different `node_distro` preserves its
      `vm_id`, address and Proxmox host (VMP-11, VMP-03).

## Known limitations

- Default sizing (3× 4GB control plane + 3× 8GB workers = 36GB of 48GB physical,
  12GB per 16GB host) exceeds one node, so the cluster only fits spread across
  three hosts. A fourth 8GB worker does not fit; 6GB workers or more RAM is the
  precondition (0019 MIX-12). Round-robin placement is load distribution, not a
  scheduler; capacity math is the operator's job.
- An in-place distro swap runs the cluster at N-1 workers for its duration,
  because there is no headroom for a temporary node on a host already carrying
  12GB. The workload set therefore has to fit on two workers.
- Placement is index-based round-robin: changing the Proxmox node count
  changes where re-created VMs land (existing VMs are untouched; a duplicate
  `vm_id` on another node fails loudly at `qm create`).
- VM creation shells out to `qm` over SSH rather than using the
  [`community.general.proxmox_kvm`](https://docs.ansible.com/ansible/latest/collections/community/general/proxmox_kvm_module.html)
  API module — a deliberate tradeoff to avoid requiring Proxmox API tokens.
