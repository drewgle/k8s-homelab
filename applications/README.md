# Applications

Everything deployed *onto* the Kubernetes cluster lives here and is
reconciled by Argo CD from this repository. Nothing in this tree is applied
by hand.

> **Status: not built yet.** The layout and rules below are the contract
> defined by [spec 0007](../docs/specs/0007-gitops-bootstrap.md); the
> directories appear as that spec is implemented. Until then this file
> describes what will exist, not what does.

## The dividing line

| | Ansible | Argo CD |
|---|---|---|
| Style | push, imperative runs | pull, continuously reconciled |
| Scope | bare metal → Proxmox → Ceph → VMs → Kubernetes + CNI | everything deployed onto the cluster |
| Ends | when a kubeconfig exists | never |

`infrastructure/` is the first column. This directory is the second.

## Structure

```
applications/
├── bootstrap/
│   ├── argocd/            # Argo CD install (kustomize, pinned version)
│   └── root.yaml          # App-of-apps: watches system/ and apps/
├── system/                # Platform services, one directory per component
│   ├── metallb/
│   ├── envoy-gateway/     # Gateway API implementation
│   ├── cert-manager/
│   ├── sealed-secrets/
│   ├── storage/           # CSI driver + StorageClasses
│   ├── monitoring/        # kube-prometheus-stack, Loki, Alloy
│   ├── backup/            # Velero
│   └── cloudflare-tunnel/ # public exposure
└── apps/                  # End-user workloads, one directory per app
```

Each component directory is a Kustomize base plus an Argo CD `Application`
manifest picked up by the root app.
[Sync waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
order the system components: sealed-secrets and MetalLB before the Gateway,
the Gateway before anything that attaches a route to it.

## Deployment

There is exactly one imperative step in the whole system, and it is a
playbook, not a `kubectl apply`:

```bash
ansible-playbook playbooks/kubernetes/01-gitops-bootstrap.yml
```

It installs Argo CD and the root Application. Everything after that is a git
commit. If you find yourself running `kubectl apply` against this cluster,
something has gone wrong — the change belongs in git, and Argo CD will
either apply it or tell you why it can't.

## Secrets

Secrets are committed, encrypted, as
[SealedSecrets](https://github.com/bitnami-labs/sealed-secrets):

```bash
kubectl create secret generic my-secret \
  --dry-run=client --from-literal=key=value -o yaml \
  | kubeseal --format yaml > applications/apps/my-app/sealed-secret.yaml
```

The sealing key is the single point of failure for every secret in the repo:
without it, a rebuilt cluster cannot decrypt anything committed here. Backing
it up is covered by [spec 0015](../docs/specs/0015-backup-and-recovery.md).

Never commit a plain `Secret`. The repo has a
[pre-commit](../.pre-commit-config.yaml) gitleaks hook, but it is a backstop,
not the control.

## Which components, and why

| Component | Chosen | Rejected, and why |
|-----------|--------|-------------------|
| Ingress | Gateway API via Envoy Gateway | ingress-nginx — retired by Kubernetes SIG Network in March 2026, no further security fixes |
| Log collection | Grafana Alloy | Promtail — end of life March 2026 |
| Storage | CSI against the existing Proxmox Ceph pool | Longhorn — replication on top of already-replicated disks; Rook — a second Ceph cluster |
| Load balancing | MetalLB (L2) | Cilium L2 announcements, pending the CNI decision |

The reasoning behind each is in the spec that owns it —
[0008](../docs/specs/0008-kubernetes-storage.md) for storage,
[0009](../docs/specs/0009-platform-services.md) for the rest.

## Conventions

- **Kustomize** for configuration; Helm charts are consumed through it rather
  than installed directly, so the rendered output stays reviewable
- **Pin every version** — image tags and chart versions, never `latest`.
  Renovate opens the bump PRs
- **Resource requests and limits** on every workload
- **Health and readiness probes** on every workload
- A newcomer should be able to read one `system/<component>/` directory and
  understand that component's role without opening another repo

## Making a service public

Private by default. Public exposure goes through Cloudflare
([spec 0012](../docs/specs/0012-public-exposure-cloudflare.md)) and requires
a PR that:

1. Adds the hostname to the tunnel ingress ConfigMap
2. Adds a Cloudflare Access policy, or a README note explaining why the
   app's own authentication suffices
3. States what data the service exposes and why public access is needed
