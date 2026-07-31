# Specs

Design specs for the work this repo plans to do. Each spec describes one unit
of work in enough detail that a contributor (or a future session) can pick it
up — or change it safely — without re-deriving the design.

## Conventions

- New specs start from [TEMPLATE.md](TEMPLATE.md).
- Files are numbered `NNNN-short-title.md`. The number is allocation order,
  not reading order — a spec written later for a lower layer of the stack
  keeps its high number and is placed in the index where it belongs.
- A spec's numbered requirements record the *intended behavior* of the
  subsystem they cover: once that subsystem is built, a change that violates
  one of them is a regression unless the spec is updated in the same change.
- Requirement IDs (`INIT-03`, `CEPH-06`, ...) are stable references —
  playbook comments cite them (`BMP-06`, `CNI-04`, `CNI-09`, ...).
  Append new IDs rather than renumbering; a dropped or replaced requirement is
  deleted outright and its number stays retired, never reused — git history
  keeps the old text. A spec that nothing cites yet may be rewritten freely,
  IDs and all.
- Removing or rewording a requirement is not done until the citations are
  clean: grep `infrastructure/` and `docs/` for the ID before calling it
  finished.
- Each spec states which repo goals it serves, what is out of scope, and
  concrete acceptance criteria so "done" is testable.
- When implementation reveals a better design, update the spec — the spec is
  the record of the *current* plan, not a historical artifact.

## Index

In dependency order, bottom of the stack first:

| Spec | Title | Serves goals |
|------|-------|--------------|
| [0001](0001-bare-metal-provisioning.md) | Bare-metal Proxmox provisioning | Learning (proxmox, ansible) |
| [0002](0002-initial-node-setup.md) | Initial node setup | Learning (proxmox, ansible) |
| [0003](0003-proxmox-cluster.md) | Proxmox VE cluster formation | Learning (proxmox) |
| [0004](0004-ceph-storage.md) | Ceph distributed storage | Learning (ceph, proxmox) |
| [0005](0005-node-hardening.md) | Node security hardening | Learning (proxmox, security) |
| [0006](0006-vm-platform.md) | VM platform for Kubernetes nodes | Learning |
| [0013](0013-talos-cluster-lifecycle.md) | Talos Kubernetes cluster lifecycle | Learning (k8s, talos) |
| [0016](0016-cluster-networking-cilium.md) | Cluster networking: Cilium | Learning (k8s, networking), presentation |
| [0007](0007-gitops-bootstrap.md) | GitOps bootstrap with Flux | GitOps, learning, organization |
| [0008](0008-kubernetes-storage.md) | Kubernetes persistent storage on Ceph | GitOps, learning (ceph) |
| [0009](0009-platform-services.md) | Core platform services | GitOps, learning (k8s) |
| [0017](0017-self-hosted-forge.md) | Self-hosted forge: Forgejo and Actions runners | GitOps, learning (k8s, CI), organization |
| [0018](0018-ci-pipelines.md) | CI pipelines on Forgejo Actions | GitOps, learning (CI), organization |
| [0012](0012-public-exposure-cloudflare.md) | Public service exposure via Cloudflare | TLS/exposure, GitOps |
| [0015](0015-backup-and-recovery.md) | Backup and disaster recovery | GitOps, learning, organization |
| [0011](0011-meetup-presentation.md) | 90-minute meetup presentation | Presentation |

## Repo goals (for reference)

1. Fully GitOps-backed deployment
2. Learn k8s, Proxmox, Ansible, Ceph and related tooling
3. ~90-minute presentation for a local developer meetup
4. Keep the repo organized and approachable for homelab newcomers
5. All private services are served over HTTPS with Let's Encrypt
   certificates; all public services are exposed through Cloudflare
