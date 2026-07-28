# 0015 — Backup and disaster recovery

**Status:** Draft
**Serves goals:** Fully GitOps-backed deployment; learning (Proxmox, Ceph,
k8s); repo organization
**Depends on:** [0007 GitOps bootstrap](0007-gitops-bootstrap.md);
[0008 Kubernetes storage](0008-kubernetes-storage.md) for PV backup

## Context

The architecture doc publishes recovery objectives — RTO under four hours,
RPO under one hour, monthly DR drills — that nothing in the repo implements
or tests. Spec 0008 defers volume backup to "a future Velero/backup spec"
that did not exist. Published objectives with no mechanism behind them are
worse than none: they read as a guarantee and they are a guess.

This spec exists to make the objectives real or replace them with honest
ones. It starts from what recovery actually requires, which is not one
mechanism but four, because the layers fail independently:

| Layer | What is lost if it goes | Recovered from |
|-------|-------------------------|----------------|
| Repository | everything's definition | git remote (already offsite) |
| Cluster identity | ability to administer an existing cluster at all | Talos `secrets.yaml` / kubeadm PKI + etcd |
| Kubernetes objects | workloads, config, RBAC | git (declared) + Velero (undeclared) |
| Volume data | user data — the only unrecreatable thing | volume snapshots + offsite copy |

The GitOps principle carries the third row: anything reconciled from
`applications/` is rebuilt by re-running the bootstrap, not restored. That is
what makes this spec small. Everything else needs a real backup.

## Goals

- The unrecreatable data — PV contents, cluster identity material — survives
  the loss of the whole Proxmox cluster.
- One documented, *tested* recovery procedure per row above, with a measured
  duration so the RTO number is observed rather than asserted.
- Backups run unattended and their failure is visible (spec 0009's
  monitoring), because an unmonitored backup is a belief.
- Restore is exercised on a schedule, not first attempted during an outage.

## Non-goals

- Backing up the Proxmox hypervisors' OS installs. Rebuilding a node is spec
  [0001](0001-bare-metal-provisioning.md) plus a Ceph rebalance; that is
  faster and better tested than restoring a hypervisor image.
- Continuous replication or a hot standby site.
- Backing up Ceph itself as a block device. Ceph replication survives a node
  loss (spec [0004](0004-ceph-storage.md), `min_size 2`); it is not a backup
  and this spec must not present it as one.

## Design

### 1. Cluster identity (highest value, smallest data)

The material without which a *running* cluster becomes unadministerable:

- Talos: `infrastructure/linux/talos/secrets.yaml` (spec 0013, TALOS-01).
- Flatcar: the kubeadm PKI in `/etc/kubernetes/pki` on a control plane.
- The sealed-secrets sealing key (spec 0007) — without it, every committed
  SealedSecret is undecryptable and the "rebuild from git" claim is false.

All three are small, static, and secret. They go to an
[age](https://github.com/FiloSottile/age)-encrypted archive written by a
playbook to a path outside the repo, with the operator responsible for one
offsite copy. The procedure is documented; the encryption is automated so
"back up your key" is never a manual `cp`.

### 2. etcd (Flatcar only)

Talos rebuilds its control plane from the secrets bundle and machine configs.
kubeadm clusters do not: cluster state lives in etcd on the control planes. A
CronJob takes an
[etcd snapshot](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster)
hourly and ships it to the same offsite target as volume backups. This
asymmetry between the two stacks is itself a spec 0010 evaluation finding and
should be journaled there.

### 3. Kubernetes objects and volumes — Velero

[Velero](https://velero.io/) in `applications/system/backup/`, deployed by
Argo CD like everything else:

- Backend: an S3-compatible bucket. Two candidates, decided at
  implementation: a
  [Ceph RGW](https://docs.ceph.com/en/latest/radosgw/) instance on the
  existing Proxmox Ceph cluster (keeps everything in-house, but the backup
  then shares a failure domain with the thing it backs up), or an offsite
  object store. **The offsite copy is not optional** — if the only copy of
  the backup lives on the cluster being backed up, this spec has failed its
  own goal. RGW may serve as the fast local tier with replication offsite.
- Volume data via the CSI snapshot API (spec 0008 defers
  `VolumeSnapshot` support; this spec is the reason to stop deferring it).
- Schedule: daily full, hourly for namespaces flagged as carrying user data.
  The hourly cadence is what the one-hour RPO actually requires.
- Namespaces whose contents are fully declared in git are *excluded*, and the
  exclusion list is a reviewed file rather than a default — an accidental
  exclusion is silent until a restore.

### 4. Proxmox VM backups

`vzdump` to a separate physical target (a NAS or a
[Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server)
instance) for the VMs themselves, weekly. This is the cheap path back from
"a VM is corrupt" without a full re-provision, and it is the only layer that
protects against a Ceph-level disaster. It does not replace Velero: restoring
a VM restores a node, not a workload.

## Revised objectives

The current RTO/RPO numbers are replaced with per-scenario targets, each
paired with the procedure that achieves it. These are estimates until the
drill in the implementation plan measures them, and the spec MUST be updated
with measured values afterwards:

| Scenario | Target | Path |
|----------|--------|------|
| Pod or workload broken | minutes | Argo CD rollback |
| One Kubernetes node lost | < 1 hour | re-provision (0006) + rejoin (0013/0014) |
| One Proxmox node lost | < 4 hours | re-image (0001) + rejoin + Ceph rebalance |
| Cluster lost, hardware intact | < 4 hours | re-provision + bootstrap + Velero restore |
| Everything lost | days | hardware first; this is not an RTO scenario |

RPO: one hour for flagged user data, 24 hours otherwise, zero for anything
declared in git.

## Implementation plan

1. Identity backup playbook (age-encrypted, all three artifacts) — this is
   the highest-value, lowest-effort piece and does not depend on 0007.
2. `vzdump` schedule to an offsite target.
3. Velero + CSI snapshots in `applications/system/backup/`, with the
   exclusion list and the schedule.
4. etcd snapshot CronJob for the Flatcar cluster.
5. Backup-failure alerts wired into spec 0009's monitoring.
6. One full drill: destroy a cluster, restore it, **measure** each phase, and
   replace the estimates above with the observed numbers.
7. Update the architecture doc's backup section to match reality, and remove
   the unbacked "monthly DR drills" claim or schedule real ones.

## Acceptance criteria

- [ ] Every artifact in section 1 is recoverable from an encrypted archive
      that has been decrypted and verified at least once.
- [ ] A PVC's data is restorable into a rebuilt cluster with Velero, and the
      restored data is byte-verified against a known checksum.
- [ ] A backup failure produces an alert visible in Grafana, demonstrated by
      deliberately breaking the backend.
- [ ] The drill in step 6 has been performed and the objectives table
      contains measured, not estimated, durations.
- [ ] No table in this repo states a recovery objective that has not been
      measured by that drill.

## Open questions

- Ceph RGW versus an external object store as the Velero backend — an
  in-cluster backend is convenient and shares a failure domain with the data.
  The offsite requirement stands either way; RGW is a tier, not an answer.
- Whether the sealed-secrets key backup (spec 0007) should be folded into
  section 1 outright, or whether spec 0007's key handling should be replaced
  with an external secret store, which would make that row disappear.
- Retention: how long is worth keeping for a homelab, given that the storage
  cost is real and the compliance requirement is zero.
