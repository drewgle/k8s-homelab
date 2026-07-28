# 0007 — GitOps bootstrap with Flux

**Status:** Draft
**Serves goals:** Fully GitOps-backed deployment; learning k8s; repo organization

## Context

The Ansible layer produces a bare Kubernetes cluster (Talos or Flatcar) with a
CNI and nothing else. This spec defines how *everything above the cluster* gets
reconciled from this repository rather than applied by hand.

The dividing line between the two toolchains:

- **Ansible (push, imperative runs):** bare metal → Proxmox → Ceph → VMs →
  Kubernetes cluster + CNI. Ends when a kubeconfig exists.
- **Flux (pull, continuously reconciled):** everything deployed *onto* the
  cluster — platform services, storage classes, applications.

### Why Flux and not Argo CD

The architecture doc originally named Argo CD. Both are CNCF graduated projects
and either would work; Flux fits this repository better for four concrete
reasons.

**Secrets in git, not beside it.** Flux's kustomize-controller decrypts
[SOPS](https://github.com/getsops/sops) at reconcile time, so an
[age](https://github.com/FiloSottile/age)-encrypted value is a normal committed
file. Under Argo CD, SOPS requires a config-management plugin (ksops or
argocd-vault-plugin) bolted onto the repo-server, which is why the earlier draft
of this spec reached for sealed-secrets instead — and then had to introduce a
*gitignored* key directory, contradicting its own goal that secrets live in git.
SOPS also keeps secrets readable to their owner: a SealedSecret committed six
months ago cannot be decrypted back to plaintext even by the person who sealed
it, which makes rotation and review guesswork.

**Footprint.** Argo CD is five workloads (api-server, repo-server,
application-controller, redis, dex). Flux is four controllers and no database,
at roughly a quarter of the memory requests. On homelab VMs that is real
headroom.

**Renovate has a native Flux manager.** It reads `HelmRelease`,
`HelmRepository` and `OCIRepository` directly. Argo CD's install manifest and
chart pins would need hand-written regex managers.

**Copyable prior art.** The home-operations community's homelab templates are
Flux-based, which matters more for the learning goal than tool ergonomics do.

The cost is the UI. Argo CD's application tree is genuinely the better artifact
to put on a projector, which is a live concern for the meetup
(spec [0011](0011-meetup-presentation.md)); see *Visibility* below for how that
gap gets closed.

## Goals

- One command takes a freshly bootstrapped cluster to "Flux is running and
  reconciling this repo".
- Works identically on Talos and Flatcar clusters, so switching node OS
  (spec [0010](0010-node-os-evaluation.md)) does not change the app layer.
- The full application state is recoverable from git alone: destroy the VMs,
  re-run the playbooks, and every workload returns without manual steps.
- Secrets live in git, encrypted — no gitignored files holding cluster state.

## Non-goals

- Multi-cluster or multi-environment overlays (single homelab cluster).
- CI-driven image building or a container registry (possible future spec).
- Image automation (Flux writing new tags back to git) — Renovate already owns
  version bumps, and two things racing to edit the same manifests is a
  correctness problem, not a feature.
- Migrating the Ansible infrastructure layer itself to GitOps.

## Design

### Flux manages Flux

Flux is installed and upgraded by the
[Flux Operator](https://github.com/controlplaneio-fluxcd/flux-operator), which
reconciles a single `FluxInstance` resource describing the desired Flux version,
component set, and git source.

This matters for two reasons. It makes Flux's own version a declarative,
Renovate-managed field rather than a pinned manifest someone re-applies by hand.
And it avoids `flux bootstrap`, whose whole model is to **commit and push** the
Flux install into the repository — a non-starter here, because git credentials
are hardware-key protected and no automation in this repo talks to a remote.
`FluxInstance` reaches the same end state with a resource that a human commits
normally.

### Bootstrap playbook

A single OS-agnostic playbook, following the existing numbering convention:

```
infrastructure/ansible/playbooks/kubernetes/01-gitops-bootstrap.yml
```

It runs on localhost against the generated kubeconfig
(`infrastructure/linux/{talos,flatcar}/generated/kubeconfig`, selected via a
`vm_type` variable, defaulting to autodetection of whichever file exists). It:

1. Installs the Flux Operator from its pinned OCI Helm chart into
   `flux-system`.
2. Creates the `sops-age` Secret holding the age private key, from an
   Ansible Vault-encrypted variable. This must exist *before* Flux reconciles
   anything, or every SOPS-encrypted manifest fails to decrypt.
3. Applies `applications/flux/instance.yaml` — the `FluxInstance` pointing at
   this repository's `applications/` tree.
4. Waits for the root `Kustomization` to report `Ready` and prints where to
   find the Flux status commands.

Steps 1–3 are the only `kubectl apply`s in the system; everything else is a git
commit.

### Repository layout

```
applications/
├── flux/
│   ├── operator/          # Flux Operator chart pin (applied once by Ansible)
│   ├── instance.yaml      # FluxInstance: Flux version, components, git source
│   └── kustomizations/    # One Flux Kustomization per component, with dependsOn
├── system/                # Platform services, one directory per component
│   ├── metallb/
│   ├── envoy-gateway/     # Gateway API implementation (spec 0009)
│   ├── cert-manager/
│   ├── storage/           # CSI driver + StorageClasses (spec 0008)
│   ├── monitoring/        # kube-prometheus-stack, Loki, Alloy (spec 0009)
│   ├── backup/            # Velero (spec 0015)
│   └── cloudflare-tunnel/ # public exposure (spec 0012)
└── apps/                  # End-user workloads, one directory per app
```

Each component directory is a Kustomize base. Ordering is expressed as
`dependsOn` between Flux
[Kustomizations](https://fluxcd.io/flux/components/kustomize/kustomizations/) —
an explicit dependency graph rather than Argo CD's integer sync waves, and Flux
holds a dependent back until its dependency is *health-checked*, not merely
applied. MetalLB before Envoy Gateway; the Gateway before anything attaching an
`HTTPRoute` to it; cert-manager before anything requesting a Certificate.

Note there is no `sealed-secrets/` directory: SOPS needs no in-cluster
controller, only the age key from bootstrap step 2.

### Secrets

[SOPS](https://github.com/getsops/sops) with an
[age](https://github.com/FiloSottile/age) keypair. A `.sops.yaml` at the repo
root sets creation rules so that only `data` and `stringData` fields are
encrypted — resource kind, name and namespace stay in cleartext, so diffs
remain reviewable and `kustomize build` still parses the file.

Flux `Kustomization`s that contain secrets set `decryption.provider: sops` with
`secretRef: sops-age`.

The age *private* key is the one secret that cannot live in this repo in
plaintext. It is stored in the Ansible Vault-encrypted variables file — so it is
committed, encrypted, and the Ansible Vault password becomes the single
out-of-band secret for the whole system. That password and the recovery
implications are spec [0015](0015-backup-and-recovery.md)'s problem. The public
key is committed in cleartext in `.sops.yaml`; anyone can encrypt, only the
cluster and the vault holder can decrypt.

Contributor workflow (`sops --encrypt`, editing an existing encrypted file in
place) documented in `applications/README.md`.

### Git access

Flux needs read access to this repository. The repo is public, so the
`FluxInstance` sync source needs no credentials. If it is ever made private,
Flux gets its own **read-only deploy key** — never a personal credential —
supplied the same way as the age key.

### Visibility

Flux has no bundled UI. Closing that gap, in increasing order of effort:

- `flux get all -A` and `flux events` — enough day to day.
- The [Flux plugin for Headlamp](https://headlamp.dev/) — a real
  reconciliation tree in a browser, and Headlamp is useful for the rest of the
  cluster regardless.
- [Capacitor](https://github.com/gimlet-io/capacitor) — a small standalone Flux
  dashboard.

Spec [0009](0009-platform-services.md) exposes whichever of these is chosen
through the Gateway.

### Version management

[Renovate](https://docs.renovatebot.com/) already manages `versions.yaml`
files. Extend [renovate.json](../../renovate.json) with:

- The built-in [`flux` manager](https://docs.renovatebot.com/modules/manager/flux/),
  which understands `HelmRelease`, `HelmRepository` and `OCIRepository` under
  `applications/`.
- A custom manager for `spec.distribution.version` in
  `applications/flux/instance.yaml` and the operator chart pin, using the same
  `# renovate:` comment convention as the existing `versions.yaml` managers.

Same policy shape as today: patch bumps automerge after a soak window,
minor/major require review.

### Linting

Add to the existing [lint workflow](../../.github/workflows/lint.yml):

- `kustomize build --enable-helm` over every kustomization under
  `applications/` — catches broken manifests before Flux does.
- [kubeconform](https://github.com/yannh/kubeconform) for schema validation,
  with the Flux CRD schemas registered.
- `sops --verify`-style check that nothing under `applications/` contains an
  unencrypted `Secret` — the gitleaks pre-commit hook is a backstop, not the
  control.

## Implementation plan

1. Age keypair generated; `.sops.yaml` creation rules; `sops_age_key` added to
   the Ansible Vault-encrypted variables file.
2. `applications/flux/` — operator chart pin, `FluxInstance`, root
   `Kustomization`s; rewrite `applications/README.md` for this layout and the
   SOPS workflow.
3. `playbooks/kubernetes/01-gitops-bootstrap.yml` + README entry in the root
   quick start (step 5, after cluster creation).
4. CI: kustomize build + kubeconform + unencrypted-Secret check.
5. Renovate `flux` manager and the `FluxInstance` version manager.

## Acceptance criteria

- [ ] Fresh Talos cluster → bootstrap playbook → `flux get all -A` all `Ready`,
      with no manual `kubectl` steps beyond the playbook's own.
- [ ] The same passes on a Flatcar cluster.
- [ ] Full teardown (`remove-vms.yml`) and rebuild restores all committed
      applications, including secrets, given only the repo and the Ansible
      Vault password.
- [ ] A SOPS-encrypted Secret round-trips: encrypt, commit, reconcile, and the
      decrypted value is correct in the cluster.
- [ ] A deliberately broken kustomization fails CI before merge.
- [ ] Renovate opens a PR for an outdated Flux version.

## Open questions

- Whether to enable Flux's notification-controller at bootstrap or defer it to
  spec 0009 with the rest of the alerting story. Leaning defer — there is no
  audience for alerts until Grafana exists.
- Headlamp vs Capacitor for the dashboard. Decide in spec 0009, where the
  Gateway and TLS to expose it actually exist; until then, CLI only.
- Whether one Flux `Kustomization` per component is the right granularity, or
  whether `system/` should reconcile as a single unit. Starting per-component
  because `dependsOn` and per-component health gating are the point; revisit if
  the boilerplate outgrows the benefit.
