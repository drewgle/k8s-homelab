# 0003 — Proxmox VE cluster formation

**Status:** Implemented
**Serves goals:** Learning (Proxmox); repo organization
**Implementing files:** `infrastructure/ansible/playbooks/proxmox/03-cluster-create.yml`,
`cluster-add-node.yml`, `health-check.yml`

## Context

Joins the standalone PVE nodes into one
[corosync](https://corosync.github.io/corosync/)-backed cluster (see the
[PVE Cluster Manager docs](https://pve.proxmox.com/wiki/Cluster_Manager)) so
VMs can migrate between nodes and the web UI manages everything from any node.
`03-cluster-create.yml` is one-shot cluster formation; `cluster-add-node.yml`
grows an existing cluster.

## Requirements

- **CLU-01** Cluster creation MUST refuse to run when any node already
  belongs to a cluster (points at `cluster-add-node.yml` instead), and MUST
  require ≥ 2 inventory nodes. 3+ nodes are expected in practice — see
  CLU-07.
- **CLU-02** The first host in the `proxmox` inventory group is the cluster
  creator; the cluster name comes from `proxmox_cluster_name`
  (default `homelab`).
- **CLU-03** All nodes MUST have verified IP connectivity to each other
  before any cluster command runs.
- **CLU-04** Remaining nodes join the creator over the management IP; after
  formation every node's `pvecm status` MUST succeed and the web UI (port
  8006) MUST answer on every node.
- **CLU-05** Each node's hostname MUST resolve to its management IP locally
  (standard PVE installer behavior — provided by spec 0001 or manual
  install). corosync and `pvecm add` depend on it.
- **CLU-06** `cluster-add-node.yml` MUST auto-detect which inventory hosts
  are already members vs new (via `pvecm status`), add only the new ones,
  and exit cleanly when there is nothing to do.
- **CLU-07** Quorum expectations: a 2-node cluster cannot survive a node
  loss (no majority). The supported steady state is an odd number of votes —
  3+ nodes, or 2 nodes plus a
  [QDevice](https://pve.proxmox.com/wiki/Cluster_Manager#_corosync_external_vote_support)
  (not automated here).

## Interfaces

Consumes: `proxmox_cluster_name`, optional `proxmox_cluster_network`
(defaults to the management network derived from facts).

## Acceptance criteria

- [ ] `pvecm status` on every node: expected votes = node count,
      `Quorate: Yes`.
- [ ] `pvecm nodes` lists every inventory host.
- [ ] Web UI on any node shows all nodes green.
- [ ] Re-running `03-cluster-create.yml` against the formed cluster fails
      fast with the "already exists" guard (CLU-01).
- [ ] `health-check.yml` passes: critical services running, cluster status
      reported.

## Known limitations

- `pvecm create` is invoked with the legacy `--bindnet0_addr` flag; modern
  pvecm prefers `--link0`. Works today, worth modernizing.
- Node joins use `--force` and tolerate per-node failure (status is printed,
  the play continues) — a partially formed cluster is possible and only
  visible in the output/acceptance checks.
- Removing a node from the cluster is not automated (Proxmox makes departed
  node names sticky; manual `pvecm delnode` per the
  [official docs](https://pve.proxmox.com/wiki/Cluster_Manager#pvecm_remove_node)).
