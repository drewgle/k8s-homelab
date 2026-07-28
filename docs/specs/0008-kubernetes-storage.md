# 0008 — Kubernetes persistent storage on Ceph

**Status:** Draft
**Serves goals:** Fully GitOps-backed deployment; learning Ceph
**Depends on:** [0007 GitOps bootstrap](0007-gitops-bootstrap.md)

## Context

The Proxmox cluster already runs a replicated Ceph cluster
(`playbooks/proxmox/04-ceph-deploy.yml`), but Kubernetes workloads currently
have no persistent storage at all. The architecture doc lists Longhorn, which
would build a *second* replicated storage layer on top of VM disks that are
already Ceph-backed — replication on replication, and it sidesteps the goal
of learning Ceph. This spec chooses a CSI driver that exposes the existing
Ceph cluster to Kubernetes instead.

## Goals

- PVCs provision dynamically against the existing Proxmox Ceph pool.
- Deployed and configured entirely through GitOps
  (`applications/system/storage/`).
- A default StorageClass suitable for general workloads, plus a clear story
  for what happens to volumes when the node OS is swapped (Talos ↔ Flatcar).

## Non-goals

- CephFS / RWX volumes and object storage (RGW) — revisit when a workload
  needs them.
- Volume snapshots and backup (belongs to a future
  [Velero](https://velero.io/)/backup spec).
- Longhorn — explicitly rejected, see below.

## Options considered

| Option | How it works | Trade-offs |
|--------|--------------|------------|
| [**proxmox-csi-plugin**](https://github.com/sergelogvinov/proxmox-csi-plugin) (recommended) | Talks to the Proxmox API (port 8006); PVs are Proxmox-managed disks on any PVE storage, including the Ceph pool | Only needs API reachability from the VM VLAN to the management network; volumes visible as disks in the PVE UI; topology-aware placement |
| [ceph-csi](https://github.com/ceph/ceph-csi) (RBD, external cluster) | Pods talk directly to Ceph mons/OSDs (ports 3300/6789 + OSD range) | More Ceph learning surface, but requires routing the VM VLAN into the Ceph public network — a wider firewall opening than a single API port |
| [Rook](https://rook.io/) (managed Ceph in-cluster) | Runs its own Ceph cluster inside Kubernetes | Duplicates the existing Ceph investment; heavyweight for a homelab |
| [Longhorn](https://longhorn.io/) | Replicated storage over VM disks | Replication-on-replication over Ceph-backed disks; ignores the Ceph learning goal |

**Recommendation: proxmox-csi-plugin.** Smallest network exposure (one API
endpoint instead of the whole Ceph public network), reuses the existing pool,
and keeps storage operations observable in tooling already in use. ceph-csi
remains the fallback if the Proxmox API layer proves limiting — the decision
should be re-validated during implementation and this spec updated.

## Design

- `applications/system/storage/` contains the CSI driver (Helm chart via
  Kustomize) plus
  [StorageClasses](https://kubernetes.io/docs/concepts/storage/storage-classes/):
  - `ceph-rbd` (default): the Ceph pool, `ReclaimPolicy: Delete`.
  - `ceph-rbd-retain`: same pool, `Retain`, for data that must survive
    accidental PVC deletion.
- A dedicated, least-privilege
  [PVE API token](https://pve.proxmox.com/wiki/User_Management) for the CSI
  driver (VM.Audit, Datastore.Allocate on the Ceph storage only), stored as
  a SealedSecret.
- Network prerequisite: the VM VLAN (`vm_subnet`) must reach the management
  network on TCP 8006 only. Documented in
  [NETWORK.md](../../infrastructure/linux/talos/NETWORK.md) and enforced no
  wider than that.
- OS-swap behavior: PVs are Proxmox disks independent of the VMs, but
  `remove-vms.yml` deletes VMs — document that `Retain`-class volumes survive
  as orphaned Proxmox disks and how to re-adopt them, and that `Delete`-class
  data is expected to be rebuilt from git (GitOps principle) or backups.

## Implementation plan

1. Create the PVE API token + role via an addition to the proxmox playbooks
   (so it is reproducible, not clicked together in the UI).
2. `applications/system/storage/` kustomization with the driver and both
   StorageClasses; SealedSecret for the token.
3. Network/firewall documentation update.
4. Smoke-test workload (PVC + writer pod) used for the acceptance criteria,
   kept under `applications/apps/storage-smoke/` or as a documented one-off.

## Acceptance criteria

- [ ] `kubectl apply` is never run manually: the driver arrives via Argo CD.
- [ ] A PVC against `ceph-rbd` binds, and its data survives deleting and
      rescheduling the consuming pod onto a different node.
- [ ] The backing image is visible in the Proxmox/Ceph tooling
      (learning goal: trace one volume end to end and note it in the
      evaluation journal).
- [ ] A `ceph-rbd-retain` volume's disk survives `remove-vms.yml` +
      re-provisioning, and the re-adoption procedure is documented and tested
      once.

## Open questions

- Does proxmox-csi-plugin's topology handling fit the round-robin VM
  placement used by `proxmox_vm`? Verify volumes follow pods correctly during
  live migration of the underlying VM.
- Update the architecture doc's Longhorn references once this lands.
