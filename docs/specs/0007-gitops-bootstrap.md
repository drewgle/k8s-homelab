# 0007 — GitOps bootstrap with Argo CD

**Status:** Draft
**Serves goals:** Fully GitOps-backed deployment; learning k8s; repo organization

## Context

The Ansible layer produces a bare Kubernetes cluster (Talos or Flatcar) with a
CNI and nothing else. The architecture doc already names
[Argo CD](https://argo-cd.readthedocs.io/en/stable/) as the GitOps tool and
[Kustomize](https://kustomize.io/) as the configuration mechanism; this spec
turns that into a concrete bootstrap path so that *everything above the cluster* is reconciled
from this repository rather than applied by hand.

The dividing line between the two toolchains:

- **Ansible (push, imperative runs):** bare metal → Proxmox → Ceph → VMs →
  Kubernetes cluster + CNI. Ends when a kubeconfig exists.
- **Argo CD (pull, continuously reconciled):** everything deployed *onto* the
  cluster — platform services, storage classes, applications.

## Goals

- One command takes a freshly bootstrapped cluster to "Argo CD is running and
  syncing this repo".
- Works identically on Talos and Flatcar clusters, so switching node OS
  (spec [0010](0010-node-os-evaluation.md)) does not change the app layer.
- The full application state is recoverable from git alone: destroy the VMs,
  re-run the playbooks, and every workload returns without manual steps.
- Secrets live in git safely (encrypted), not in gitignored files.

## Non-goals

- Multi-cluster or multi-environment overlays (single homelab cluster).
- CI-driven image building or a container registry (possible future spec).
- Migrating the Ansible infrastructure layer itself to GitOps.

## Design

### Bootstrap playbook

A single OS-agnostic playbook, following the existing numbering convention:

```
infrastructure/ansible/playbooks/kubernetes/01-gitops-bootstrap.yml
```

It runs on localhost against the generated kubeconfig
(`infrastructure/linux/{talos,flatcar}/generated/kubeconfig`, selected via a
`vm_type` variable, defaulting to autodetection of whichever file exists). It:

1. Installs Argo CD from the pinned manifest/kustomization in
   `applications/bootstrap/argocd/`.
2. Applies the root Application (`applications/bootstrap/root.yaml`) pointing
   Argo CD at this repository's `applications/` tree — Argo CD's
   [app-of-apps pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/).
3. Waits for the root app to reach `Synced/Healthy` and prints the Argo CD
   admin URL + initial credentials location.

This is the only `kubectl apply` in the system; everything else is Argo CD.

### Repository layout (app-of-apps)

```
applications/
├── bootstrap/
│   ├── argocd/            # Argo CD install (kustomize, pinned version)
│   └── root.yaml          # App-of-apps: watches applications/system + apps
├── system/                # Platform services, one directory per component
│   ├── metallb/
│   ├── ingress-nginx/
│   ├── cert-manager/
│   ├── sealed-secrets/
│   ├── storage/           # CSI driver + StorageClasses (spec 0008)
│   ├── monitoring/        # kube-prometheus-stack, loki (spec 0009)
│   └── cloudflare-tunnel/ # public exposure (spec 0012)
└── apps/                  # End-user workloads, one directory per app
```

Each component directory is a Kustomize base with an accompanying Argo CD
`Application` manifest picked up by the root app (directory-recurse or
[ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/)
— decided during implementation, recorded here).
[Sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
order the system components (sealed-secrets and MetalLB before ingress,
ingress before anything with an Ingress resource).

### Secrets

Bitnami [**sealed-secrets**](https://github.com/bitnami-labs/sealed-secrets)
(already named in the architecture doc):

- The controller deploys in wave 0 from `applications/system/sealed-secrets/`.
- The sealing keypair is backed up once to a gitignored
  `applications/bootstrap/sealed-secrets-key/` directory and documented as a
  "store this outside the repo" step — without it, a rebuilt cluster cannot
  decrypt existing SealedSecrets.
- Contributor workflow (`kubeseal` usage) documented in `applications/README.md`.

### Version management

[Renovate](https://docs.renovatebot.com/) already manages `versions.yaml`
files. Extend
[renovate.json](../../renovate.json) with managers for:

- The Argo CD version in `applications/bootstrap/argocd/`.
- Helm chart versions / container image tags under `applications/`.

Same policy shape as today: patch bumps automerge after a soak window,
minor/major require review.

### Linting

Add to the existing lint workflow: `kustomize build` over every
kustomization under `applications/` (catches broken manifests before Argo CD
does) and [kubeconform](https://github.com/yannh/kubeconform) for schema
validation.

## Implementation plan

1. `applications/bootstrap/` — Argo CD kustomization + root app; rewrite
   `applications/README.md` to describe this layout and the kubeseal workflow.
2. `playbooks/kubernetes/01-gitops-bootstrap.yml` + README entry in the root
   quick start (step 5, after cluster creation).
3. `applications/system/sealed-secrets/` with key-backup documentation.
4. CI: kustomize build + kubeconform job.
5. Renovate managers for the new tree.

## Acceptance criteria

- [ ] Fresh Talos cluster → bootstrap playbook → Argo CD UI reachable, root
      app `Synced/Healthy`, with no manual `kubectl` steps.
- [ ] The same passes on a Flatcar cluster.
- [ ] Full teardown (`remove-vms.yml`) and rebuild restores all committed
      applications without manual intervention (given the sealed-secrets key
      backup).
- [ ] A deliberately broken kustomization fails CI before merge.
- [ ] Renovate opens PRs for an outdated Argo CD version.

## Open questions

- Plain directory-recurse root app vs ApplicationSet — start with the simple
  root app; revisit if per-component sync policy gets repetitive.
- Argo CD ingress + TLS depends on spec [0009](0009-platform-services.md);
  until then the UI is reached via port-forward.
