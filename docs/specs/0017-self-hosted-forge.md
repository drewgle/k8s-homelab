# 0017 — Self-hosted forge: Forgejo and Actions runners

**Serves goals:** Fully GitOps-backed deployment; learning (k8s, CI); repo
organization
**Depends on:** [0007 GitOps bootstrap](0007-gitops-bootstrap.md);
[0008](0008-kubernetes-storage.md) (RWO volumes, `ceph-rbd-retain`);
[0009](0009-platform-services.md) (MetalLB, the shared Gateway, cert-manager)
**Affects:** [0007](0007-gitops-bootstrap.md) (Flux's git source, and its claim
that no automation here talks to a remote);
[0015](0015-backup-and-recovery.md) (a new piece of identity material, and the
first namespace that is *not* recoverable from git)

## Context

Every forge function this repo uses is currently GitHub's: the remote, code
review, the lint workflow, Renovate's pull requests, and — via
`https://github.com/{{ github_username }}.keys` — the SSH keys that make a
freshly installed Proxmox node reachable at all (spec
[0002](0002-initial-node-setup.md), INIT-01). A repo whose stated goal is a
self-hosted, rebuildable platform depends on a hosted service at the very
bottom of its own bootstrap.

This spec moves the forge into the homelab: [Forgejo](https://forgejo.org/) as
the authoritative remote, its built-in
[Actions](https://forgejo.org/docs/latest/user/actions/) as CI, its built-in
package registry for images, and GitHub demoted to a push mirror that serves two
narrow purposes — an offsite copy of repository content, and the source Flux
bootstraps from on a cold cluster.

That last point is the whole difficulty. Flux would reconcile the cluster from a
repository hosted *on that cluster*. This spec treats the resulting ordering
problem as its central design question rather than a footnote, because the naive
arrangement does not merely degrade — it deadlocks a rebuild permanently.

## Decision

**Forgejo**, deployed by Flux, with **Forgejo Actions** runners in-cluster,
Forgejo's **built-in package registry**, and **PostgreSQL** as the database.
Reachable on the LAN only. Forgejo is authoritative; it **push-mirrors** to the
existing `github.com/drewgle/k8s-homelab`.

Flux's steady-state source is the in-cluster Forgejo, reached over
cluster-internal Service DNS. **Every cold boot starts from the GitHub mirror**
and cuts over to Forgejo automatically once the forge is healthy.

### Options considered

| Option | CI | Notes |
|--------|----|-------|
| [Forgejo](https://forgejo.org/) (chosen) | built-in Actions | Community-governed hard fork of Gitea, no CLA. One service, one database, no OAuth wiring between forge and CI |
| [Gitea](https://about.gitea.com/) | built-in Actions | Larger integration ecosystem, commercially backed. Functionally equivalent here; the governance model is the only real differentiator |
| Forge + [Woodpecker](https://woodpecker-ci.org/) | separate | Lighter agent than `act_runner` and no GitHub-Actions emulation quirks, at the cost of a second server, second database, and an OAuth app |
| GitLab CE | built-in | Rejected on footprint alone — several GB of RAM against a 24 GB worker budget already committed by spec 0009 |

Two further options were considered and rejected, and both deserve recording
because they are *better engineering* on one axis than what was chosen:

**GitHub stays Flux's source permanently**, with Forgejo authoritative only for
humans and CI. This removes the circular dependency entirely — the forge could
be down for a week and Flux would not notice. It was rejected because it leaves
the most load-bearing part of the platform dependent on a hosted service, which
is precisely what this spec exists to fix. The trade is real and should be
stated plainly: **this spec accepts a less robust reconciliation path in
exchange for the self-hosting and learning goals.**

**Ansible installs the CSI driver, MetalLB and Forgejo before Flux**, removing
the circularity by moving the forge below the GitOps line. Rejected because it
drags three platform components across spec 0007's Ansible/Flux dividing line.
Note the contrast with Cilium, which legitimately takes that exemption under
[0016](0016-cluster-networking-cilium.md) CNI-08: without a CNI *no pod runs at
all*, including Flux's, so there is no alternative. Flux, by contrast, can
bootstrap perfectly well from an external remote — so the forge does not earn
the same exemption.

## Requirements

- **FORGE-01** Forgejo MUST be the authoritative remote. GitHub MUST be a
  push-mirror target only; no automation and no human MUST push to GitHub
  directly, because the next mirror push overwrites it.
- **FORGE-02** Flux MUST reach Forgejo over the cluster-internal Service DNS
  name and plain HTTP, never the LAN hostname. This keeps MetalLB, the Gateway,
  cert-manager and external DNS out of Flux's source path — see *Bootstrap
  ordering* below.
- **FORGE-03** The bootstrap playbook's Flux sync URL MUST be a variable
  (`flux_git_url`) that **defaults to the GitHub mirror**. Cold boot and
  disaster recovery MUST be the same command, not two procedures.
- **FORGE-04** The Flux `Kustomization` carrying the `FluxInstance` MUST be
  gated by `dependsOn` and health checks on a fully seeded Forgejo. Applying it
  ungated deadlocks a rebuild permanently.
- **FORGE-05** The mirror credential MUST be a machine token scoped to write
  exactly one GitHub repository. The operator's hardware-key-protected identity
  MUST NOT be used by any automation.
- **FORGE-06** The GitHub mirror MUST NOT be treated as a backup of forge
  state. It carries repository content only.
- **FORGE-07** Git-over-SSH MUST be served by a dedicated MetalLB
  `LoadBalancer` Service on its own pinned IP, separate from the shared
  Gateway. The IP MUST be pinned via `metallb.io/loadBalancerIPs` so it
  survives a rebuild.
- **FORGE-08** Forgejo's SSH host keys MUST be generated once and committed
  SOPS-encrypted. Regenerated host keys break every client's `known_hosts` and
  every SSH-based CI checkout after a volume rebuild.
- **FORGE-09** Forgejo's `SECRET_KEY` and `INTERNAL_TOKEN` MUST be generated
  once and committed SOPS-encrypted. They encrypt the mirror token, OAuth
  secrets and 2FA material at rest in the database; regenerating them silently
  renders a restored database partly unusable.
- **FORGE-10** Forgejo MUST run as a single replica with
  `strategy: Recreate`, on a `ceph-rbd-retain` volume. `RollingUpdate` against
  a single-attach RWO volume deadlocks waiting for the old pod to detach.
- **FORGE-11** Nothing under `applications/system/` MUST reference a container
  image hosted in the in-cluster registry. Only `applications/apps/` may. A
  platform component pulling from a registry that Flux itself deploys is an
  unrecoverable cold boot.
- **FORGE-12** Runners MUST have no Kubernetes identity:
  `automountServiceAccountToken: false` and zero `RoleBinding`s or
  `ClusterRoleBinding`s. The Docker backend needs no API access.
- **FORGE-13** A `CiliumNetworkPolicy` MUST deny runner egress to the
  management VLAN `192.168.1.0/24`, the API server, the cluster VIP, the node
  address range `192.168.100.201–.239` (spec [0006](0006-vm-platform.md),
  VMP-12), and the kubelet and Talos API ports (50000/50001/tcp), on every
  node. Spec 0008 opens VM VLAN → management on TCP 8006 for the CSI
  driver; that rule MUST be scoped to the CSI driver's pods, or a CI job can reach
  the hypervisors underneath its own cluster.
- **FORGE-15** Runners MUST be registered at organization scope, not instance
  scope, MUST carry an explicit label so workflows request them deliberately,
  and fork/untrusted-contributor triggers MUST be disabled. Anyone who can push
  to a repo a runner serves has code execution in that pod.
- **FORGE-16** If the repository is ever made private, Flux's read credential
  MUST be delivered by the bootstrap playbook from the Ansible Vault file, the
  same way as the age key. It MUST NOT be a SOPS file inside the repository it
  is needed in order to read.
- **FORGE-17** Every image tag and chart version MUST be pinned, per
  `applications/README.md`. Renovate owns the bumps.
- **FORGE-18** The forge namespace MUST be backed up by a mechanism that does
  not depend on CSI volume snapshots, whose availability is spec 0008's open
  question.
- **FORGE-19** Runners run on Talos nodes — there is no
  other kind. Rootless DinD MUST therefore be validated against Talos's
  defaults (read-only rootfs, default seccomp profile, no host shell) before
  any workflow depends on it, in a namespace carrying the relaxed PodSecurity
  labels scoped to `forge-runners` only. If rootless DinD proves unworkable on
  Talos, the fallbacks in preference order are: a kaniko/buildah-style
  daemonless builder, or a dedicated tainted CI node sized within the spec
  0006 capacity envelope.

## Design

### Bootstrap ordering and the circular dependency

Flux has **no support for multiple git remotes or automatic source failover**.
`GitRepository.spec.url` is a single string; `FluxInstance.spec.sync` likewise
takes one URL. Two `GitRepository` objects can exist, but a `Kustomization`
references exactly one `sourceRef` and nothing in Flux ever changes it. Building
failover would mean a controller that probes Forgejo and patches the source of
the thing that reconciles the cluster — a component whose failure mode is
"silently reconciling from the wrong source." That is worse than an outage you
can see, so it is deliberately not built.

Instead, the mirror is not a *fallback* — it is **the bootstrap source, used on
every cold boot**. That converts an untested emergency path into one exercised
by every rebuild and by spec 0007's own acceptance criteria.

1. **Ansible.** `01-gitops-bootstrap.yml` runs unchanged except that the sync
   URL comes from `flux_git_url`, defaulting to the GitHub mirror (FORGE-03).
2. **Flux reconciles from GitHub:** `storage` → `metallb` → `forge`.
3. **Seed.** A Job in the `forge` Kustomization creates the org and repository,
   performs a one-time clone from the public GitHub mirror, and then configures
   the push mirror back to GitHub via the Forgejo API. The clone is one-time,
   not a standing pull mirror — a pull-mirrored repository is read-only in
   Forgejo and cannot also be authoritative.
4. **Cutover.** A separate `flux-source` Kustomization contains the
   `FluxInstance` pointing at the in-cluster Forgejo, with `dependsOn` and a
   health check on the seed Job (FORGE-04). When it applies, the Flux Operator
   updates the `GitRepository`, source-controller re-clones from Forgejo, and
   steady state is reached with no operator action.

**Why the gate is load-bearing.** The obvious arrangement — commit the Forgejo
URL and let Ansible override it to GitHub for the first run — is broken, and is
recorded here so nobody re-derives it. Flux would reconcile `instance.yaml` from
GitHub within seconds, flip its own source to a Forgejo that does not exist yet,
and stall before ever creating Forgejo. The `dependsOn` plus health-check
machinery spec 0007 already chose is what makes this self-modification
convergent instead of suicidal.

**Steady state:** the committed `instance.yaml` names Forgejo; the Ansible
default names GitHub. **Recovery** is one command — the cold-boot command:

```bash
ansible-playbook playbooks/kubernetes/01-gitops-bootstrap.yml -e flux_git_url=<github>
```

If Forgejo is broken, Flux simply stops reconciling. That is the correct
behavior: a stalled Flux changes nothing, whereas a Flux pointed at a stale
mirror would silently revert live state.

### Networking: web, registry and git-over-SSH

Two hostnames, because one name cannot resolve to two IPs sensibly:

- **`forge.internal.<domain>`** → the shared Gateway IP. Web UI, API and the
  container registry over HTTPS via `HTTPRoute`, on spec 0009's wildcard
  certificate. Sets Forgejo's `ROOT_URL`.
- **`git.internal.<domain>`** → the dedicated SSH `LoadBalancer` IP. Sets
  `SSH_DOMAIN` so the clone URLs Forgejo displays are correct.

Forgejo's **built-in SSH server** on **port 22**, not host passthrough. Host
passthrough is a VM pattern: Talos has no host sshd at all, so it is
impossible here — the built-in server is the only option. Note the
configuration trap:
`SSH_LISTEN_PORT` is the unprivileged container port (2222) while `SSH_PORT` is
what Forgejo *advertises* and must be 22; the Service maps 22 → 2222.

SSH is deliberately **not** routed through Envoy Gateway, although Gateway API
`TCPRoute` would work. Envoy Gateway is itself reconciled by Flux from git
hosted in Forgejo, so putting git transport behind Envoy means a bad Envoy
upgrade breaks the mechanism used to roll back that upgrade. This is the same
blast-radius argument spec 0016 makes for keeping Cilium out of ingress.

MetalLB IP *sharing* (`metallb.io/allow-shared-ip`) is also rejected, because it
looks attractive and fails subtly: shared IPs require matching
`externalTrafficPolicy`, spec 0009 wants `Local` on the Gateway to preserve
client source IPs, and with `Local` on both Services MetalLB must pick a single
node holding ready endpoints for *both* — coupling a single-replica Forgejo's
scheduling to Envoy's. Spend the extra address.

Allocation, pinned per FORGE-07 and authoritative in spec
[0006](0006-vm-platform.md) VMP-12: `.240` shared Gateway, `.241` Forgejo SSH,
both inside the `.240–.250` MetalLB pool.

### Flux's access to the forge

The repository stays **anonymously readable inside Forgejo**, and Flux reads it
over `http://<forgejo-service>.forge.svc.cluster.local:3000/...`. This is worth
stating as a positive design property rather than a shortcut:

- It removes MetalLB, Envoy Gateway, cert-manager and DNS from Flux's critical
  path. Flux's dependency on the forge reduces to CoreDNS, Cilium and the
  Forgejo pod — and CoreDNS and Cilium both sit *below* Flux in the Ansible
  layer.
- It creates no second chicken-and-egg, because there is no key to deliver.
- It costs nothing in confidentiality. The repository is already public on
  GitHub, and every secret in the tree is SOPS-encrypted.

The invariant that makes this safe rather than lazy:

> **Repository visibility is not a security control in this repo. SOPS is.** If
> a secret ever lands in `applications/` unencrypted, the failure is the
> unencrypted secret, not the repository's visibility.

Flux is read-only against git here by design — spec 0007 rejects both
`flux bootstrap` and image automation — so read access is all it ever needs.

### Database and volumes

**PostgreSQL** as a `StatefulSet` in the `forge` namespace, not a sidecar: a
sidecar couples the database's lifecycle to the application's, and FORGE-10
already forces `Recreate` on the Forgejo pod.

SQLite on a single PVC was the lighter option and is recorded as rejected for
one reason worth remembering — it would have saved a whole stateful component
and roughly 300–500 MiB against a worker budget spec 0009 has already largely
spent. It was rejected because Actions writes job logs and task rows
continuously, and SQLite writer-lock contention surfaces as 5xx under
concurrent runners, which caps CI concurrency at the database layer rather than
at a limit anyone chose.

Volumes, both `ceph-rbd-retain` — the forge is the first workload that earns
the retain class spec 0008 created:

- Forgejo data: repositories, the SSH host keys, attachments.
- PostgreSQL data.

Large, fast-growing, poorly-compressible data — **LFS objects, package and
container registry blobs** — should go to an S3 backend on Ceph RGW, the bucket
spec 0015 already needs. That keeps the PVC small, which makes snapshots fast
and restores cheap. Verify Forgejo's per-subsystem `[storage]` support at
implementation.

### Backup and restore

Spec 0015 states that "the GitOps principle carries the third row: anything
reconciled from `applications/` is rebuilt by re-running the bootstrap." **The
forge is the first and clearest counterexample**, and 0015's premise needs
amending rather than being left to imply the forge is recoverable from git.
Issues, pull requests, releases, users, deploy keys, webhooks, Actions secrets,
registered runners and the push-mirror configuration all live in the database
and in no manifest.

Primary mechanism: **Velero File System Backup** (kopia, via the node-agent
DaemonSet) straight to the S3 target, *not* CSI snapshots. Spec 0008 leaves
proxmox-csi-plugin's snapshot support as an open question, and the forge's
recoverability must not be contingent on the answer (FORGE-18). CSI snapshots
remain a welcome fast local tier if the driver turns out to support them.

Because a filesystem backup of a live database is crash-consistent only, add a
Velero pre-backup hook running `pg_dump`, and — independently — a weekly
`forgejo dump` CronJob to S3 as the portable, version-independent artifact.
Three tiers of decreasing fidelity and increasing robustness: Velero FSB →
`forgejo dump` → the GitHub mirror.

The mirror's limits, stated once and without softening:

> **The GitHub mirror recovers repository content only.** Not issues, pull
> requests, releases, wikis, users, organization settings, deploy keys,
> webhooks, Actions secrets, registered runners, registry blobs, or the
> push-mirror configuration itself. If both the Velero backup and the dump are
> gone, the code comes back and nothing else does.

**Restore ordering is the hard part**, because the obvious sequence races: Flux
recreates an empty PVC, Forgejo initializes a fresh database, and the restore
then fights a running Forgejo. Steps 4–6 are what a 0015 recovery drill must
actually measure:

1. Hardware and Proxmox (specs 0001–0004).
2. VMs, cluster, Cilium (0006, 0013, 0016).
3. `01-gitops-bootstrap.yml` with `flux_git_url=<github>`.
4. Flux brings up `storage` and `metallb`, then **suspend the `forge`
   Kustomization before it settles**.
5. Velero restore, or `forgejo dump` restore, into the empty volumes.
6. Resume the `forge` Kustomization. Forgejo starts against restored state.
7. Verify repository content and that the push-mirror configuration survived.
8. The health-gated `flux-source` Kustomization flips Flux to Forgejo on its
   own.

### Mirroring to GitHub

Forgejo's native push mirror, authenticated with the scoped token from
FORGE-05, pushing on commit rather than on interval alone — the mirror's sync
lag is the real RPO of the GitHub-based bootstrap path, so it is a number to
measure rather than assume.

Push-mirror configuration lives in the Forgejo database, not in git, so it is
not GitOps-declared. The seed Job configures it idempotently through the
Forgejo API (step 3 above) rather than leaving it as a setting someone clicked,
which also makes its existence a reviewable fact in the repo.

`.github/workflows/lint.yml` **stays** as a backstop, so the mirror still shows
CI status and validation keeps working when the cluster is down. The
authoritative pipelines move to Forgejo Actions in spec
[0018](0018-ci-pipelines.md).

### Actions runners

`act_runner` in a dedicated `forge-runners` namespace with a rootless
Docker-in-Docker sidecar sharing an `emptyDir` socket.

Be honest about the boundary: **rootless DinD reduces but does not eliminate
the need for elevated container privileges.** Design as though the runner pod
is container-escape-adjacent, which means the real isolation is at the
namespace, network and node level, not the container level:

- No cluster identity at all (FORGE-12). One line of YAML turns "CI holds a
  token to the cluster Flux administers" into "CI has no cluster identity."
- `CiliumNetworkPolicy`: default-deny egress, then allow DNS, the Forgejo
  Service, and `world` for pulling actions and dependencies — with the
  exclusions in FORGE-13 carved out of that world rule, plus the pod CIDR
  denied except Forgejo, so a compromised job cannot reach Prometheus, Grafana,
  Velero or Flux's own controllers. This is the first concrete application of
  the default-deny baseline spec 0016 defers to "once there are applications."
- `ResourceQuota` and `LimitRange` on the namespace, as a backstop against a
  workflow that requests the whole cluster.
- One replica, concurrency 1 to start — roughly 1.3 GiB requested and ~5 GiB
  peak against the worker RAM spec 0009 is already spending on Prometheus,
  Loki, Grafana, Cilium, Envoy and Velero.
- An explicit `sizeLimit` (~20 GiB) on the DinD graph store `emptyDir`.
  Unbounded image-layer growth on node ephemeral storage evicts neighbours, and
  never the neighbour you would have chosen.

A dedicated tainted CI node is the stronger posture, and it is FORGE-19's
documented fallback. It costs a third of the worker capacity to non-CI
workloads, so it waits until the runner's behavior on Talos justifies it.

"If a fourth worker appears" needs correcting, though: per spec 0006's
capacity envelope a fourth 8 GiB worker does not fit in 48 GiB of physical
RAM. The precondition is 6 GiB workers or more RAM, not simply a decision to
add one.

**Registry credentials:** prefer the per-job token Forgejo injects
automatically — ephemeral, nothing stored. Only if its package-write scope
proves insufficient, create a `ci-bot` user with a scoped token held as an
organization-level Actions secret, *not* in SOPS: it is a Forgejo-issued
credential consumed by Forgejo, and committing it would mean maintaining it in
two places. That path is one more reason FORGE-09's `SECRET_KEY` is
backup-critical.

### Renovate

Renovate moves to a scheduled Forgejo Actions workflow running the Renovate CLI
against the Forgejo repository, so its pull requests land where they can
actually be merged. This is not optional polish: a push mirror is one-way, so
pull requests raised on GitHub would be clobbered by the next mirror push, and
spec 0007 depends on Renovate exclusively owning version bumps. Details in spec
0018.

## Implementation plan

Blocked on specs 0007, 0008 and 0009 being implemented — the forge needs Flux,
a CSI driver and MetalLB before any of this can run.

1. Pin `.240`/`.241` against spec 0006's VMP-12 address plan, which resolved
   the IP-range conflict this spec surfaced.
2. `applications/system/forge/` — Forgejo Helm chart pinned and consumed
   through Kustomize, PostgreSQL `StatefulSet`, both PVCs, `HTTPRoute`, the SSH
   `LoadBalancer` Service, and the SOPS-encrypted `SECRET_KEY`,
   `INTERNAL_TOKEN` and SSH host keys.
3. The seed Job: org, repository, one-time clone from GitHub, push-mirror
   configuration via the Forgejo API.
4. `applications/system/flux-source/` — the `FluxInstance` pointing at Forgejo,
   with `dependsOn` and health checks on the seed Job.
5. `flux_git_url` in `vars.yml.example` and the bootstrap playbook, defaulting
   to the GitHub mirror.
6. `applications/system/forge-runners/` — runner, DinD sidecar,
   `CiliumNetworkPolicy`, quota, and the FORGE-19 Talos validation.
7. Velero: add the forge namespace to the file-system-backup set with the
   `pg_dump` pre-hook; add the weekly `forgejo dump` CronJob.
8. Amend the specs and docs this one affects: 0007 (git source, the
   remote-credential invariant, the registry non-goal, linting), 0015 (the
   `SECRET_KEY` row, the CSI-snapshot assumption, the recoverable-from-git
   premise), 0009 (MetalLB pool accounting), `NETWORK.md` (the IP ranges), and
   `applications/README.md` (the new directories and FORGE-11).
9. Migrate the pipelines themselves — spec 0018.

## Acceptance criteria

- [ ] From a cold cluster, `01-gitops-bootstrap.yml` with no arguments reaches
      a running Forgejo with the repository present, and Flux's source has
      flipped to the in-cluster URL **without operator action**.
- [ ] `git clone` over SSH and over HTTPS both succeed from a LAN workstation,
      using the advertised clone URLs unmodified.
- [ ] A commit pushed to Forgejo appears on GitHub within the measured mirror
      interval, and that interval is written down.
- [ ] Destroy and recreate the Forgejo volumes, restore from Velero, and the
      repository, issues, and registry contents all return — and the SSH host
      key is unchanged, so no client sees a host-key warning.
- [ ] Stop Forgejo entirely: Flux reports a stalled source and **changes
      nothing** in the cluster.
- [ ] With Forgejo still down, the recovery command brings Flux back to
      reconciling from GitHub.
- [ ] A workflow runs on the in-cluster runner, builds an image, and pushes it
      to the Forgejo registry.
- [ ] From inside a runner job: `curl` to the Kubernetes API fails, `curl` to
      `192.168.1.101:8006` fails, and `kubectl` finds no service-account token
      — each verified by a failed connection, not by the policy object
      existing.
- [ ] Renovate opens a pull request **in Forgejo**.
- [ ] `.github/workflows/lint.yml` still passes on the mirror.

## Known limitations

- **Flux cannot fail over between sources.** Recovery is a deliberate
  one-command re-run, not automatic. This is a choice — see *Bootstrap
  ordering*.
- **Cold boot depends on mirror freshness.** If the mirror is stale, a rebuild
  reconciles stale forge manifests. Push-on-commit mirroring keeps the window
  small but does not close it.
- **Rootless DinD is the largest residual risk in this spec.** It likely still
  needs elevated privileges, so a container escape in a CI job is the realistic
  worst case; FORGE-12 to FORGE-15 exist to bound the damage rather than to
  prevent it.
- **Single replica, no HA.** Spec 0008 makes RWX an explicit non-goal, so
  multi-replica Forgejo is structurally unavailable, not a deferred choice. Any
  forge restart is a brief CI and reconciliation outage.
- **The forge is the one namespace not recoverable from git**, which makes it
  the standing exception to the model in spec 0015 and in
  `applications/README.md`.
- **Spec 0002's GitHub dependency is untouched.** Proxmox nodes still fetch
  root SSH keys from `github.com/<user>.keys`, so bare-metal provisioning
  remains dependent on GitHub regardless of this spec. Moving it would mean
  serving keys from a forge that does not exist yet at that point in the
  bootstrap — a genuine ordering constraint, not an oversight.
- **`SECRET_KEY` loss is partial data loss** even with a good database backup:
  the mirror token, OAuth secrets and 2FA material become undecryptable.

## Open questions

- ~~The IP-range conflict is blocking and needs an owning change.~~
  **Closed** by the address plan at spec [0006](0006-vm-platform.md) VMP-12,
  which adopts this spec's proposed fix — workers `.211-.239`, MetalLB pool
  `.240-.250` — with no second-cluster VIP carve-out. `.240` and `.241` are
  pinned there for the shared Gateway and FORGE-07's SSH service.
- Does Flux's `healthChecks` gate correctly on a `Job` reaching `Complete`?
  The automatic cutover depends on it. If not, the cutover becomes an explicit
  operator-run play and FORGE-04 needs rewording.
- Does proxmox-csi-plugin implement the CSI snapshot API (spec 0008's open
  question)? FORGE-18 is written so the answer does not matter, but 0015's text
  currently assumes snapshots.
- Can `docker:dind-rootless` run without `privileged: true` **on Talos** —
  under its read-only rootfs and default seccomp profile? Now that every node
  is Talos this is on the critical path for CI (FORGE-19), and it determines
  whether the runner isolation is defense-in-depth or the only defense.
- Does the automatic Actions job token carry sufficient package-write scope, or
  is a stored `ci-bot` token unavoidable?
- Does the Forgejo chart accept SSH host keys via a Secret, or is an
  initContainer needed to place them in `data/ssh/`?
- What does `forgejo dump` actually include when LFS and packages are on an S3
  backend? If it excludes them, the bucket itself is the backup for that data
  and the spec should say so.
- Nothing prunes old image tags, so registry storage grows monotonically. Spec
  0015 already flags retention as open; registry blobs make it concrete.
- Should the forge eventually host more than this repository? Scoped to one
  repository for now; the seed Job and mirror pattern are written so a second
  repository is additive.
