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
  - **VMP-07** **Superseded by VMP-12 below.** *Historical text: Coexistence
    invariant: the two stacks MUST NOT collide on any address …*
  ```

  This gives three things: `grep -rn "Superseded by" docs/specs/` finds every dead
  ID with no registry to maintain, the old text stays greppable so a stale
  playbook comment can be traced back, and a reader scanning the list sees the
  demotion before reading the sentence. When the historical text has itself
  stopped earning its keep (its subject was removed from the repo entirely), the
  marker may shrink to a one-line tombstone — git history keeps the prose.
- **Append the replacement in the same spec when the *subject* stays local; put it
  in the new spec when the *decision* moves.** VM identity stays 0006's subject,
  so VMP-04's replacement is VMP-11 in 0006. One rule, one home — do not state it
  in both places.
- **A superseded requirement may be reinstated** when its replacement is itself
  retired before being built. Flip the original back to in-force with a dated
  note and tombstone the replacement's ID.
- **Amend in place with no new ID** when a requirement's intent survives and only
  its wording changes.
- **Record it at the top of the affected spec**, so the supersession is visible
  without reading every requirement:

  ```markdown
  **Superseded requirements:** VMP-04 → VMP-11; VMP-07 → VMP-12
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
| [0006](0006-vm-platform.md) | VM platform for Kubernetes nodes | Accepted | Learning |
| [0013](0013-talos-cluster-lifecycle.md) | Talos Kubernetes cluster lifecycle | Accepted | Learning (k8s, talos) |
| [0016](0016-cluster-networking-cilium.md) | Cluster networking: Cilium | Accepted | Learning (k8s, networking), presentation |
| [0007](0007-gitops-bootstrap.md) | GitOps bootstrap with Flux | Draft | GitOps, learning, organization |
| [0008](0008-kubernetes-storage.md) | Kubernetes persistent storage on Ceph | Draft | GitOps, learning (ceph) |
| [0009](0009-platform-services.md) | Core platform services | Draft | GitOps, learning (k8s) |
| [0017](0017-self-hosted-forge.md) | Self-hosted forge: Forgejo and Actions runners | Accepted | GitOps, learning (k8s, CI), organization |
| [0018](0018-ci-pipelines.md) | CI pipelines on Forgejo Actions | Draft | GitOps, learning (CI), organization |
| [0012](0012-public-exposure-cloudflare.md) | Public service exposure via Cloudflare | Draft | TLS/exposure, GitOps |
| [0015](0015-backup-and-recovery.md) | Backup and disaster recovery | Draft | GitOps, learning, organization |
| [0011](0011-meetup-presentation.md) | 90-minute meetup presentation | Draft | Presentation |

## Repo goals (for reference)

1. Fully GitOps-backed deployment
2. Learn k8s, Proxmox, Ansible, Ceph and related tooling
3. ~90-minute presentation for a local developer meetup
4. Keep the repo organized and approachable for homelab newcomers
5. All private services are served over HTTPS with Let's Encrypt
   certificates; all public services are exposed through Cloudflare

A sixth goal — trying multiple Linux distributions and evaluating how they
are managed over time — was removed on 2026-07-31 along with specs 0010, 0014
and 0019 and the Flatcar automation; the repo is Talos-only. Git history has
the details.
