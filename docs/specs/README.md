# Specs

Design specs for the work this repo plans to do. Each spec describes one unit
of work in enough detail that a contributor (or a future session) can pick it
up — or change it safely — without re-deriving the design.

## Conventions

- Files are numbered `NNNN-short-title.md`. The number is allocation order,
  not reading order — a spec written later for a lower layer of the stack
  keeps its high number and is placed in the index where it belongs.
- Statuses: `Draft` → `Accepted` → `In progress` → `Done` (or `Superseded`).
  An `Accepted` spec records the *intended behavior* of the subsystem it
  covers: once that subsystem is built, a change that violates one of the
  spec's numbered requirements is a regression unless the spec is updated in
  the same change.
- Requirement IDs in `Accepted` specs (`INIT-03`, `CEPH-06`, ...) are stable
  references; append new ones rather than renumbering.
- Each spec states which repo goals it serves, what is out of scope, and
  concrete acceptance criteria so "done" is testable.
- When implementation reveals a better design, update the spec — the spec is
  the record of the *current* plan, not a historical artifact.

## Requirement supersession

ID stability only matters where IDs are cited from outside the spec — in
`Accepted` specs, and in the playbook comments that cite them (`BMP-06`,
`CNI-04`, `CNI-05`, `CNI-06` and `CNI-09` are all cited that way). **`Draft`
specs may be rewritten in place, IDs and all**, because nothing depends on them
yet. Everything below applies to the non-`Draft` ones.

- **Never renumber, delete or reuse an ID.**
- **Supersede in place, keeping the old text verbatim and clearly demoted.**
  Strikethrough over a multi-line requirement is unreadable in both a diff and a
  browser, so use a labelled prefix and italics:

  ```markdown
  - **VMP-07** **Superseded by [0019 MIX-09](0019-single-cluster-mixed-distro.md)
    and VMP-12 below.** *Historical text: Coexistence invariant: the two stacks
    MUST NOT collide on any address …*
  ```

  This gives three things: `grep -rn "Superseded by" docs/specs/` finds every dead
  ID with no registry to maintain, the old text stays greppable so a stale
  playbook comment can be traced back, and a reader scanning the list sees the
  demotion before reading the sentence.
- **Append the replacement in the same spec when the *subject* stays local; put it
  in the new spec when the *decision* moves.** VM identity stays 0006's subject,
  so VMP-04's replacement is VMP-11 in 0006. Cluster identity left 0013 entirely,
  so TALOS-01's replacement lives in 0019. One rule, one home — do not state it in
  both places.
- **Amend in place with no new ID** when a requirement's intent survives and only
  its wording changes.
- **Record it at the top of the affected spec**, so the supersession is visible
  without reading every requirement:

  ```markdown
  **Amended by:** [0019](0019-single-cluster-mixed-distro.md)
  **Superseded requirements:** VMP-04 → VMP-11; VMP-07 → VMP-12, 0019 MIX-09
  ```

  There is deliberately no global registry: a registry is a second copy of the
  truth and will drift.
- **Do not invent a "partially superseded" status.** A spec that still describes
  intended behavior stays `Accepted` and carries the `Amended by` field. Once a
  subsystem is built, amendments land in the same change as the code that makes
  them true — otherwise the specs describe a system nobody is building.
- **The supersession is not done until the citations are clean.** Grep
  `infrastructure/` and `docs/` for the retired IDs before calling it finished.

## Index

In dependency order, bottom of the stack first:

| Spec | Title | Status | Serves goals |
|------|-------|--------|--------------|
| [0001](0001-bare-metal-provisioning.md) | Bare-metal Proxmox provisioning | Accepted | Learning (proxmox, ansible) |
| [0002](0002-initial-node-setup.md) | Initial node setup | Accepted | Learning (proxmox, ansible) |
| [0003](0003-proxmox-cluster.md) | Proxmox VE cluster formation | Accepted | Learning (proxmox) |
| [0004](0004-ceph-storage.md) | Ceph distributed storage | Accepted | Learning (ceph, proxmox) |
| [0005](0005-node-hardening.md) | Node security hardening | Accepted | Learning (proxmox, security) |
| [0006](0006-vm-platform.md) | VM platform for Kubernetes nodes | Accepted | Learning, distro evaluation |
| [0013](0013-talos-cluster-lifecycle.md) | Talos Kubernetes cluster lifecycle | Accepted | Learning (k8s, talos), distro evaluation |
| [0014](0014-flatcar-cluster-lifecycle.md) | Flatcar Kubernetes cluster lifecycle | Accepted | Learning (k8s, kubeadm), distro evaluation |
| [0016](0016-cluster-networking-cilium.md) | Cluster networking: Cilium | Accepted | Learning (k8s, networking), presentation |
| [0019](0019-single-cluster-mixed-distro.md) | One cluster, per-node Linux distributions | Draft | Distro evaluation, learning, organization |
| [0007](0007-gitops-bootstrap.md) | GitOps bootstrap with Flux | Draft | GitOps, learning, organization |
| [0008](0008-kubernetes-storage.md) | Kubernetes persistent storage on Ceph | Draft | GitOps, learning (ceph) |
| [0009](0009-platform-services.md) | Core platform services | Draft | GitOps, learning (k8s) |
| [0017](0017-self-hosted-forge.md) | Self-hosted forge: Forgejo and Actions runners | Accepted | GitOps, learning (k8s, CI), organization |
| [0018](0018-ci-pipelines.md) | CI pipelines on Forgejo Actions | Draft | GitOps, learning (CI), organization |
| [0012](0012-public-exposure-cloudflare.md) | Public service exposure via Cloudflare | Draft | TLS/exposure, GitOps |
| [0015](0015-backup-and-recovery.md) | Backup and disaster recovery | Draft | GitOps, learning, organization |
| [0010](0010-node-os-evaluation.md) | Node OS evaluation: distro as a node property | Draft | Distro evaluation, presentation |
| [0011](0011-meetup-presentation.md) | 90-minute meetup presentation | Draft | Presentation |

## Repo goals (for reference)

1. Fully GitOps-backed deployment
2. Learn k8s, Proxmox, Ansible, Ceph and related tooling
3. Try Linux distributions and evaluate how they are managed over time
4. ~90-minute presentation for a local developer meetup
5. Keep the repo organized and approachable for homelab newcomers
6. All private services are served over HTTPS with Let's Encrypt
   certificates; all public services are exposed through Cloudflare
