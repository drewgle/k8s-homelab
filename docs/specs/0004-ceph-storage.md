# 0004 — Ceph distributed storage

**Status:** Accepted
**Serves goals:** Learning (Ceph, Proxmox); repo organization
**Planned files:** `infrastructure/ansible/playbooks/proxmox/04-ceph-deploy.yml`
(orchestrator), `ceph/01-common.yml`, `ceph/02-cluster-init.yml`,
`ceph/03-osd-add.yml`, `ceph/status.yml`, `ceph/add-node.yml`,
`ceph-expand.yml`, `verify-ceph.yml`

## Context

Provides replicated block storage across the PVE nodes for VM disks and,
later, Kubernetes persistent volumes (spec
[0008](0008-kubernetes-storage.md)). `04-ceph-deploy.yml` chains common →
cluster-init → osd-add → status; `ceph-expand.yml` chains common → add-node
→ osd-add → status for growth. All Ceph management goes through
[`pveceph`](https://pve.proxmox.com/wiki/Deploy_Hyper-Converged_Ceph_Cluster),
Proxmox's supported tooling, so the cluster is fully visible in the PVE web
UI's Ceph panel.

## Requirements

- **CEPH-01** Deployment MUST require ≥ 3 nodes (replication size 3 needs
  them; also gives a monitor majority).
- **CEPH-02** The first three inventory hosts run monitors and managers;
  `add-node.yml` tops the count back up to 3 if the cluster is ever below.
- **CEPH-03** Public and cluster networks come from `ceph_public_network`
  (default `192.168.1.0/24`) and `ceph_cluster_network` (default
  `10.0.1.0/24`), applied via `pveceph init`. The configuration lives in
  `/etc/pve/ceph.conf` and is therefore identical on every node by
  construction
  ([Proxmox cluster filesystem](https://pve.proxmox.com/wiki/Proxmox_Cluster_File_System_%28pmxcfs%29)).
- **CEPH-04** Cluster credentials are managed by `pveceph` in `/etc/pve`
  (pmxcfs-replicated); the playbooks MUST NOT copy keyrings by hand.
- **CEPH-05** A default `rbd` pool MUST be created with the RBD application,
  [`size 3` / `min_size 2`](https://docs.ceph.com/en/latest/rados/operations/pools/)
  (data survives one node loss and stays writable),
  [autoscaled placement groups](https://docs.ceph.com/en/latest/rados/operations/placement-groups/),
  and is registered as a Proxmox storage entry
  (`pveceph pool create --add_storages`).
- **CEPH-06** OSD candidacy: every whole disk that is exactly not `sda`, is
  unmounted, and is not already a Ceph device
  ([`ceph-volume lvm list`](https://docs.ceph.com/en/latest/ceph-volume/)) is
  claimed via `pveceph osd create`. **This is destructive by design** — the
  OS lives on `sda` only (BMP-06), and any other disk attached to a node is
  Ceph's.
- **CEPH-07** `02-cluster-init.yml` MUST refuse to run when
  `/etc/pve/ceph.conf` already exists (growth goes through
  `ceph-expand.yml`).
- **CEPH-08** `ceph/status.yml` and `verify-ceph.yml` MUST be runnable at
  any time without changing state.
- **CEPH-09** Ordering invariant: nodes MUST already be Proxmox cluster
  members (spec [0003](0003-proxmox-cluster.md)) — `pveceph` operates
  through the cluster filesystem.

## Interfaces

Consumes: `ceph_public_network`, `ceph_cluster_network`, optional
`ceph_pool` (pool name, default `rbd`). Assumes the cluster-network
interface (e.g. `10.0.1.x` on a second NIC) is configured out-of-band —
nothing in the repo configures it.

## Acceptance criteria

- [ ] `ceph -s` reports `HEALTH_OK`, 3 mons in quorum, all OSDs `up`/`in`.
- [ ] `ceph df` shows the `rbd` pool; `rbd create`/`rbd remove` round-trip
      works (exercised by `verify-ceph.yml`).
- [ ] `pvesm status` lists the pool as an active RBD storage, and the PVE
      web UI's Ceph panel shows the cluster.
- [ ] Pulling one node keeps the pool available (min_size 2) and health
      returns to `HEALTH_OK` after recovery.
- [ ] `verify-ceph.yml` summary reports all checks OK.
- [ ] Re-running `04-ceph-deploy.yml` against a healthy cluster fails fast
      at the CEPH-07 guard; re-running `03-osd-add.yml` finds no new disks
      and changes nothing.

## Known limitations

- If a node ever boots from NVMe instead of `sda`, its boot disk would be
  claimed as an OSD candidate — the exclusion is by device name, tied to
  BMP-06 keeping the OS on `sda`.
- The Ceph *cluster* network NIC configuration is manual (see CEPH.md);
  with a single NIC everything rides the public network.
- `pveceph install` pins whatever Ceph release the current PVE version
  defaults to; major Ceph upgrades follow PVE upgrades and are not automated
  here.
