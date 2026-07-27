# 0006 — VM platform for Kubernetes clusters

**Status:** Implemented
**Serves goals:** Learning (Proxmox, k8s); distro evaluation; repo organization
**Implementing files:** `infrastructure/ansible/roles/proxmox_vm/`,
`playbooks/talos/01-provision-vms.yml`, `playbooks/flatcar/01-provision-vms.yml`,
`playbooks/remove-vms.yml`

## Context

The bridge between the Proxmox layer and the Kubernetes layer: a shared role
that turns inventory definitions into running VMs, used identically by the
Talos and Flatcar provisioning playbooks so the node-OS evaluation (spec
[0010](0010-node-os-evaluation.md)) swaps cleanly.

## Requirements

- **VMP-01** Both node OSes provision through the shared `proxmox_vm` role —
  bridge setup (`tasks/bridge.yml`) and VM create/start (`tasks/create.yml`).
  OS-specific behavior is limited to ISO choice, cloud-init/ignition
  snippets, and extra `qm create` args.
- **VMP-02** VM networking uses a VLAN-aware bridge (`vm_bridge_name`,
  default `vmbr1`) persisted in `/etc/network/interfaces` (managed block)
  and applied with `ifreload -a`; VM NICs are tagged with `vm_vlan_id`
  (default 100).
- **VMP-03** VMs are distributed round-robin across all `proxmox` inventory
  hosts; a `proxmox_node` hostvar pins a VM to a specific node. The install
  ISO MUST be present on every node (downloaded in the prepare play) so any
  placement works.
- **VMP-04** Every Kubernetes node host in inventory MUST define a
  cluster-unique `vm_id`. Talos uses 2xx, Flatcar 3xx; both map to the same
  IPs (see VMP-07).
- **VMP-05** VM disks are created on `vm_storage` (default `local-lvm` —
  which is why BMP-06 mandates the ext4+LVM install).
- **VMP-06** VM creation and start are idempotent: an existing `vm_id` on
  the target node short-circuits creation; a running VM short-circuits
  start. Re-running a provision playbook is safe.
- **VMP-07** Exclusivity invariant: Talos and Flatcar node definitions share
  the same IP addresses, so only one stack may be provisioned at a time.
  Switching stacks goes through `remove-vms.yml -e vm_type=<talos|flatcar>`.
- **VMP-08** Teardown (`remove-vms.yml`) MUST work across all Proxmox nodes
  (each node removes the target VMs that exist locally), require interactive
  confirmation unless `-e force=true`, destroy disks (`qm destroy --purge`),
  and clean up cloud-init/ignition snippets.
- **VMP-09** Provisioning is only complete when each VM answers on its
  OS-appropriate port: Talos maintenance API (50000/tcp) or Flatcar SSH
  (22/tcp).
- **VMP-10** VM hardware baseline: q35 machine type, host CPU, virtio-scsi
  with iothread, serial console (`--serial0 socket --vga serial0`), QEMU
  guest agent enabled, `--onboot 1`.

## Interfaces

Consumes: `vm_bridge_name`, `vm_vlan_id`, `vm_storage`, `vm_gateway`,
`vm_subnet`, `vm_cidr_bits`, `vm_cp_*`/`vm_worker_*` sizing vars; per-host
`vm_id`, `ansible_host`, optional `proxmox_node`. ISO versions come from
`infrastructure/linux/{talos,flatcar}/versions.yaml` (Renovate-managed where
a datasource exists).

## Acceptance criteria

- [ ] After a provision run, `qm list` across the nodes shows the VMs spread
      round-robin (or pinned per `proxmox_node`).
- [ ] Re-running the provision playbook reports zero changes.
- [ ] All VMs reach their readiness port (VMP-09) within the playbook's
      timeout.
- [ ] `remove-vms.yml` empties every node of that stack's VMs and the
      snippets directory of its configs; the opposite stack can then
      provision onto the same IPs.

## Known limitations

- Default sizing (3× 4GB control plane + 3× 8GB workers = 36GB) exceeds one
  16GB node — round-robin placement is load distribution, not a scheduler;
  capacity math is the operator's job.
- Placement is index-based round-robin: changing the Proxmox node count
  changes where re-created VMs land (existing VMs are untouched; a duplicate
  `vm_id` on another node fails loudly at `qm create`).
- VM creation shells out to `qm` over SSH rather than using the
  `community.general.proxmox_kvm` API module — a deliberate tradeoff to
  avoid requiring Proxmox API tokens.
