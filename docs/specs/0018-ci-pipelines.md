# 0018 — CI pipelines on Forgejo Actions

**Status:** Draft
**Serves goals:** Fully GitOps-backed deployment; learning (CI); repo
organization
**Depends on:** [0017 self-hosted forge](0017-self-hosted-forge.md) (the forge,
the runners and the registry); [0007](0007-gitops-bootstrap.md) (what there is
to validate)
## Context

Spec 0017 builds the forge and the runners but deliberately migrates no
pipelines, to keep that spec readable. This spec is the pipeline content: what
actually runs, on what trigger, and what it is allowed to touch.

The starting point is a single GitHub Actions job — `yamllint` plus
`ansible-lint` ([lint.yml](../../.github/workflows/lint.yml)). Spec 0007
describes the validation this repo needs beyond that: `kustomize build`, schema
validation, and a check that no unencrypted `Secret` reaches `applications/`.
That list is inherited here rather than restated there.

The governing constraint is inherited from spec 0007 and is not reopened: **CI
does not apply anything to the cluster.** Flux is the only thing that applies
changes; CI's job is to reject bad commits before Flux ever sees them.

## Goals

- Every pipeline that matters runs on homelab hardware, on the repo's own
  forge.
- A broken manifest fails in CI, not in a Flux reconciliation error nobody is
  watching.
- GitHub keeps a working backstop pipeline, so validation survives the cluster
  being down.

## Non-goals

- CI applying manifests, running `kubectl apply`, or holding cluster
  credentials. Spec 0017's FORGE-12 makes this structural, not a policy.
- **Flux image automation** — Flux writing new tags back to git. Spec 0007
  rejected this because Renovate exclusively owns version bumps, and two
  writers racing on the same manifests is a correctness problem rather than a
  feature. Building images (below) does not change that: the tag bump is still
  Renovate's.
- Multi-architecture image builds.
- Self-hosted runners for the GitHub backstop workflow.

## Design

### Validation pipelines

On every push and pull request, mirroring and extending the current lint job:

- `yamllint` and `ansible-lint`, with the existing `.yamllint` and
  `.ansible-lint` configuration unchanged.
- `kustomize build --enable-helm` over every kustomization under
  `applications/`.
- [kubeconform](https://github.com/yannh/kubeconform) with the Flux CRD schemas
  registered.
- A check that nothing under `applications/` contains an unencrypted `Secret`.
  The [gitleaks](../../.pre-commit-config.yaml) pre-commit hook is a backstop,
  not the control.

### Image builds

For anything in `applications/apps/` that needs a locally built image: build and
push to the Forgejo registry using the per-job token from spec 0017, tagged by
commit SHA. Bound by spec 0017's FORGE-11 — a built image may never be consumed
by anything under `applications/system/`.

### Workflows must respect what the node provides

Every runner lands on a Talos node, so host behavior — the default seccomp
profile, the read-only rootfs, no host shell — is uniform and known in
advance. Image builds are the case that matters: rootless DinD's viability on
Talos is spec [0017](0017-self-hosted-forge.md) FORGE-19's open validation,
and workflows MUST NOT assume host capabilities beyond what that validation
establishes.

### Scheduled maintenance

- **Self-hosted Renovate**, on a cron schedule, running the Renovate CLI against
  the Forgejo repository. Required rather than optional: the GitHub mirror is
  one-way, so Renovate's pull requests must be raised where they can be merged.
  The existing [renovate.json](../../renovate.json) — including the
  `versions.yaml` regex managers and the Talos/Kubernetes soak rules — carries
  over; only the platform and credentials change.
- **Backup verification**, asserting that the most recent Velero backup and
  `forgejo dump` exist and are within their expected age. An unverified backup
  is a belief (spec [0015](0015-backup-and-recovery.md)).
- **Drift reporting**, surfacing Flux Kustomizations that are not `Ready`, into
  spec [0009](0009-platform-services.md)'s alerting rather than a dashboard
  nobody opens.

### The GitHub backstop

`.github/workflows/lint.yml` stays, running the fast subset — the two linters —
so the mirror shows CI status and validation still works during a cluster
outage. Deliberate duplication, scoped to the checks that need no cluster and no
registry.

## Implementation plan

1. `.forgejo/workflows/lint.yml` — port the existing two linters, confirm the
   runner executes them, and compare against the GitHub job's result.
2. Add `kustomize build`, kubeconform and the unencrypted-`Secret` check, once
   `applications/` has content worth validating.
3. Renovate workflow, credentials, and dependency dashboard on Forgejo; disable
   the GitHub-side Renovate app in the same change so the two never both open
   pull requests.
4. Backup verification and drift reporting.
5. Image build workflow, when the first app needs one.

## Acceptance criteria

- [ ] A pull request with a deliberately broken kustomization fails on the
      in-cluster runner before it can be merged.
- [ ] A pull request adding an unencrypted `Secret` under `applications/` fails.
- [ ] Renovate opens a pull request in Forgejo, and no duplicate appears on
      GitHub.
- [ ] The backup verification job fails when a backup is deliberately aged out
      or deleted.
- [ ] The GitHub backstop still passes on the mirror after the migration.
- [ ] An image built by CI is pullable from the Forgejo registry by a workload
      in `applications/apps/`.
- [ ] The image build workflow runs successfully on a Talos node under the
      constraints FORGE-19's validation established.

## Open questions

- How much of the GitHub Actions ecosystem `act_runner` needs. Third-party
  actions are fetched from GitHub at job runtime, which quietly reintroduces an
  internet dependency into local CI; pinning them by SHA, vendoring them, or
  preferring plain `run:` steps are the options.
- Whether backup verification and drift reporting belong in CI at all, or as
  Kubernetes `CronJob`s in the monitoring namespace with Prometheus alerts.
  Leaning `CronJob` — a scheduled pipeline that fails silently is the same
  problem it exists to detect.
- Whether pull requests should be required at all in a single-operator repo, or
  whether the validation workflow on direct pushes to `main` is enough. Branch
  protection has value as a habit and as presentation material even with one
  human.
