# Specs

Design specs for planned work, plus behavioral specs for the subsystems that
already exist. Each spec describes one unit of work or one implemented area
in enough detail that a contributor (or a future session) can pick it up —
or change it safely — without re-deriving the design.

The aspirational documentation elsewhere in this repo
([architecture](../architecture/README.md), [applications](../../applications/README.md))
describes the target end state; these specs are the ordered, actionable path
to get there.

## Conventions

- Files are numbered `NNNN-short-title.md`. The number is allocation order,
  not reading order — a spec written later for an already-built subsystem
  keeps its high number and is placed in the index where it belongs.
- Statuses: `Draft` → `Accepted` → `In progress` → `Done` (or `Superseded`).
  Specs for already-built subsystems use `Implemented`: they record the
  *current intended behavior* — a change that violates one of their numbered
  requirements is a regression unless the spec is updated in the same change.
- Requirement IDs in implemented specs (`INIT-03`, `CEPH-06`, ...) are stable
  references; append new ones rather than renumbering.
- Each spec states which repo goals it serves, what is out of scope, and
  concrete acceptance criteria so "done" is testable.
- When implementation reveals a better design, update the spec — the spec is
  the record of the *current* plan, not a historical artifact.

## Index

In dependency order, bottom of the stack first:

| Spec | Title | Status | Serves goals |
|------|-------|--------|--------------|
| [0001](0001-bare-metal-provisioning.md) | Bare-metal Proxmox provisioning | Implemented | Learning (proxmox, ansible) |
| [0002](0002-initial-node-setup.md) | Initial node setup | Implemented | Learning (proxmox, ansible) |
| [0003](0003-proxmox-cluster.md) | Proxmox VE cluster formation | Implemented | Learning (proxmox) |
| [0004](0004-ceph-storage.md) | Ceph distributed storage | Implemented | Learning (ceph, proxmox) |
| [0005](0005-node-hardening.md) | Node security hardening | Implemented | Learning (proxmox, security) |
| [0006](0006-vm-platform.md) | VM platform for Kubernetes clusters | Implemented | Learning, distro evaluation |
| [0013](0013-talos-cluster-lifecycle.md) | Talos Kubernetes cluster lifecycle | Implemented | Learning (k8s, talos), distro evaluation |
| [0014](0014-flatcar-cluster-lifecycle.md) | Flatcar Kubernetes cluster lifecycle | Implemented | Learning (k8s, kubeadm), distro evaluation |
| [0016](0016-cluster-networking-cilium.md) | Cluster networking: Cilium | Accepted | Learning (k8s, networking), presentation |
| [0007](0007-gitops-bootstrap.md) | GitOps bootstrap with Flux | Draft | GitOps, learning, organization |
| [0008](0008-kubernetes-storage.md) | Kubernetes persistent storage on Ceph | Draft | GitOps, learning (ceph) |
| [0009](0009-platform-services.md) | Core platform services | Draft | GitOps, learning (k8s) |
| [0012](0012-public-exposure-cloudflare.md) | Public service exposure via Cloudflare | Draft | TLS/exposure, GitOps |
| [0015](0015-backup-and-recovery.md) | Backup and disaster recovery | Draft | GitOps, learning, organization |
| [0010](0010-node-os-evaluation.md) | Node OS evaluation: Talos vs Flatcar | Draft | Distro evaluation, presentation |
| [0011](0011-meetup-presentation.md) | 90-minute meetup presentation | Draft | Presentation |

## Repo goals (for reference)

1. Fully GitOps-backed deployment
2. Learn k8s, Proxmox, Ansible, Ceph and related tooling
3. Try Linux distributions and evaluate how they are managed over time
4. ~90-minute presentation for a local developer meetup
5. Keep the repo organized and approachable for homelab newcomers
6. All private services are served over HTTPS with Let's Encrypt
   certificates; all public services are exposed through Cloudflare
