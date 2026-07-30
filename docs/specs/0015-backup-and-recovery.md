# 0015 — Backup and disaster recovery

**Status:** Draft
**Serves goals:** Fully GitOps-backed deployment; learning (Proxmox, Ceph,
k8s); repo organization
**Depends on:** [0007 GitOps bootstrap](0007-gitops-bootstrap.md);
[0008 Kubernetes storage](0008-kubernetes-storage.md) for PV backup
**Amended by:** [0019](0019-single-cluster-mixed-distro.md) — one identity
artifact instead of two, and etcd backup is symmetric

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
| Cluster identity | ability to administer an existing cluster at all | the cluster PKI bundle, committed SOPS-encrypted (spec [0019](0019-single-cluster-mixed-distro.md), MIX-02) |
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

The material without which a *running* cluster becomes unadministerable. Spec
[0019](0019-single-cluster-mixed-distro.md) collapsed this from two per-distro
items to one:

- The cluster PKI bundle, `infrastructure/linux/cluster/pki/` (0019 MIX-02,
  MIX-07) — the Kubernetes, etcd and front-proxy CAs, the service-account signing
  keypair, the bootstrap token, and the Talos-specific machine material. Every
  distro's identity artifact is rendered from it, so it is the same one file
  regardless of what any node is running. Talos's `secrets.yaml` and kubeadm's
  `/etc/kubernetes/pki` are now derived and reproducible (0013 TALOS-12, 0014
  FLAT-02), so neither needs backing up.
- The SOPS age private key (spec 0007) — without it, every committed
  encrypted Secret is undecryptable and the "rebuild from git" claim is false.
  It lives in the Ansible Vault-encrypted variables file, so in practice the
  thing to protect is the **Ansible Vault password**, which is also the
  out-of-band secret for the infrastructure layer.

Because the bundle is committed encrypted, it rides along with the repository
backup in row one, and the only thing needing out-of-band protection is the Vault
password. **One secret, not three** — the clearest practical gain from 0019.

The Vault password goes to an [age](https://github.com/FiloSottile/age)-encrypted
archive written by a playbook to a path outside the repo, with the operator
responsible for one offsite copy. The procedure is documented; the encryption is
automated so "back up your key" is never a manual `cp`.

### 2. etcd (always)

This section used to be titled "Flatcar only", on the reasoning that Talos
rebuilds its control plane from the secrets bundle while kubeadm cannot. That
conflated identity with data. A control plane exists in every configuration, and
cluster state that is not in git — custom resources, Velero's own metadata, Flux's
bookkeeping — lives in etcd regardless of which distro holds the control plane.
The bundle restores *identity*; it does not restore *state*.

So the objective is symmetric and only the mechanism differs, following
`control_plane_distro` (0019 MIX-14):

- Talos: `talosctl etcd snapshot` from the control machine.
- kubeadm: a CronJob taking an
  [etcd snapshot](https://kubernetes.io/docs/tasks/administer-cluster/configure-upgrade-etcd/#backing-up-an-etcd-cluster).

Hourly, shipped to the same offsite target as volume backups. That "same objective,
different mechanism, chosen by one variable" shape is the pattern 0019 establishes
everywhere, and the *difference in effort* between the two is what belongs in spec
0010's control-plane-level matrix.

### 3. Kubernetes objects and volumes — Velero

[Velero](https://velero.io/) in `applications/system/backup/`, deployed by
Flux like everything else:

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
| Pod or workload broken | minutes | git revert, Flux reconciles |
| One Kubernetes node lost | < 1 hour | re-provision (0006) + rejoin (0019 MIX-17, specified by 0013/0014) |
| One node's distro swapped | < 30 min, no workload outage | `swap-node-distro.yml` (0019 MIX-23) |
| One Proxmox node lost | < 4 hours | re-image (0001) + rejoin + Ceph rebalance |
| Cluster lost, hardware intact | < 4 hours | re-provision + bootstrap + Velero restore |
| Control-plane distro changed | < 4 hours | rebuild + restore; **not** a swap (0019 MIX-14) |
| Everything lost | days | hardware first; this is not an RTO scenario |

RPO: one hour for flagged user data, 24 hours otherwise, zero for anything
declared in git.

## Implementation plan

1. Identity backup playbook (age-encrypted) — this is the highest-value,
   lowest-effort piece and does not depend on 0007. Since 0019 it covers the
   Vault password, because the PKI bundle itself travels with the repo.
2. `vzdump` schedule to an offsite target.
3. Velero + CSI snapshots in `applications/system/backup/`, with the
   exclusion list and the schedule.
4. etcd snapshots, by whichever mechanism `control_plane_distro` selects.
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
- [ ] A cluster is restorable from the repository plus the Vault password alone —
      no separately archived Talos secrets bundle or kubeadm PKI is needed (0019
      MIX-04, MIX-07).

## Known limitations

- The cluster PKI bundle is the one artifact whose loss means a new cluster (0019
  MIX-07). It is committed encrypted, so losing it means losing the repository
  *and* every clone — but it also means repository compromise plus age-key
  compromise is total cluster compromise. That trade is stated in 0019 and
  accepted there.

## Open questions

- Ceph RGW versus an external object store as the Velero backend — an
  in-cluster backend is convenient and shares a failure domain with the data.
  The offsite requirement stands either way; RGW is a tier, not an answer.
- Whether the Ansible Vault password (which now transitively protects the SOPS
  age key, spec 0007) needs anything beyond a password manager plus one
  offsite copy. An external secret store would remove it from this spec
  entirely, at the cost of a dependency the homelab does not otherwise need.
- Retention: how long is worth keeping for a homelab, given that the storage
  cost is real and the compliance requirement is zero.
