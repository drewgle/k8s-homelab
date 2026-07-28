# Applications

Everything deployed *onto* the Kubernetes cluster lives here and is reconciled
by [Flux](https://fluxcd.io/) from this repository. Nothing in this tree is
applied by hand.

> **Status: not built yet.** The layout and rules below are the contract
> defined by [spec 0007](../docs/specs/0007-gitops-bootstrap.md); the
> directories appear as that spec is implemented. Until then this file
> describes what will exist, not what does.

## The dividing line

| | Ansible | Flux |
|---|---|---|
| Style | push, imperative runs | pull, continuously reconciled |
| Scope | bare metal → Proxmox → Ceph → VMs → Kubernetes + CNI | everything deployed onto the cluster |
| Ends | when a kubeconfig exists | never |

`infrastructure/` is the first column. This directory is the second.

## Structure

```
applications/
├── flux/
│   ├── operator/          # Flux Operator chart pin (applied once by Ansible)
│   ├── instance.yaml      # FluxInstance: Flux version, components, git source
│   └── kustomizations/    # One Flux Kustomization per component, with dependsOn
├── system/                # Platform services, one directory per component
│   ├── metallb/
│   ├── envoy-gateway/     # Gateway API implementation
│   ├── cert-manager/
│   ├── storage/           # CSI driver + StorageClasses
│   ├── monitoring/        # kube-prometheus-stack, Loki, Alloy
│   ├── backup/            # Velero
│   └── cloudflare-tunnel/ # public exposure
└── apps/                  # End-user workloads, one directory per app
```

Flux upgrades itself: the version and component set live in
`flux/instance.yaml`, reconciled by the Flux Operator, and Renovate bumps them
like any other dependency.

Each component directory is a Kustomize base. Ordering is a dependency graph,
not a sequence — each component's Flux
[Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/)
declares `dependsOn`, and Flux holds a dependent back until its dependency
passes its health checks. MetalLB before Envoy Gateway; cert-manager before
anything requesting a Certificate; the Gateway before anything attaching a route
to it.

## Deployment

There is exactly one imperative step in the whole system, and it is a
playbook, not a `kubectl apply`:

```bash
ansible-playbook playbooks/kubernetes/01-gitops-bootstrap.yml
```

It installs the Flux Operator, creates the age decryption key Secret, and
applies the `FluxInstance`. Everything after that is a git commit. If you find
yourself running `kubectl apply` against this cluster, something has gone wrong
— the change belongs in git, and Flux will either apply it or tell you why it
can't.

Checking on it:

```bash
flux get all -A
```

```bash
flux events --for Kustomization/monitoring
```

To see what a change *would* do before pushing it:

```bash
flux diff kustomization monitoring --path applications/system/monitoring
```

## Secrets

Secrets are committed encrypted with [SOPS](https://github.com/getsops/sops)
and an [age](https://github.com/FiloSottile/age) key. Flux's
kustomize-controller decrypts them at reconcile time; there is no in-cluster
sealing controller.

Creating one:

```bash
kubectl create secret generic my-secret \
  --dry-run=client --from-literal=key=value -o yaml \
  | sops --encrypt /dev/stdin > applications/apps/my-app/secret.sops.yaml
```

Changing one later — this decrypts in place, opens your editor, and re-encrypts
on save:

```bash
sops applications/apps/my-app/secret.sops.yaml
```

The `.sops.yaml` creation rules at the repo root encrypt only `data` and
`stringData`, so kind, name and namespace stay readable in diffs and
`kustomize build` still parses the file. The age *public* key is committed
there in cleartext — anyone can encrypt a new secret without holding the
private key.

The age private key is stored in the Ansible Vault-encrypted variables file, so
the vault password is the single out-of-band secret for the entire system.
Losing it means every committed secret is undecryptable and the "rebuild from
git" claim is false; backing it up is
[spec 0015](../docs/specs/0015-backup-and-recovery.md).

Never commit a plain `Secret`. CI rejects unencrypted ones and the repo has a
[pre-commit](../.pre-commit-config.yaml) gitleaks hook, but both are backstops,
not the control.

## Which components, and why

| Component | Chosen | Rejected, and why |
|-----------|--------|-------------------|
| GitOps | Flux | Argo CD — SOPS needs a repo-server plugin, ~4× the memory footprint, no native Renovate manager ([spec 0007](../docs/specs/0007-gitops-bootstrap.md)) |
| Secrets | SOPS + age | sealed-secrets — cluster-bound key, and a sealed value cannot be read back even by its author |
| Ingress | Gateway API via Envoy Gateway | ingress-nginx — retired by Kubernetes SIG Network in March 2026, no further security fixes |
| Log collection | Grafana Alloy | Promtail — end of life March 2026 |
| Storage | CSI against the existing Proxmox Ceph pool | Longhorn — replication on top of already-replicated disks; Rook — a second Ceph cluster |
| Load balancing | MetalLB (L2) | Cilium L2 announcements, pending the CNI decision |

The reasoning behind each is in the spec that owns it —
[0007](../docs/specs/0007-gitops-bootstrap.md) for GitOps and secrets,
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
