# 0011 — 90-minute meetup presentation

**Serves goals:** Presentation; indirectly all others (the talk is the
forcing function)
**Depends on:** specs 0007–0009 for the GitOps demos;
[0013](0013-talos-cluster-lifecycle.md) for section 5 and demo D

## Context

[docs/presentation/](../presentation/) holds an abstract and one
image. The abstract promises self-hosted replacements for Google Workspace
and Dropbox, which the repo does not (yet) demonstrate — the repo's actual
strength is the *infrastructure and GitOps story*: blank hardware to a
reconciled Kubernetes platform, entirely from git. This spec scopes the talk
to what will demonstrably exist, and defines the missing materials.

## Goals

- A 90-minute talk (target ~75 minutes of content + Q&A buffer) a local
  developer audience can follow with no homelab background.
- Every claim in the talk is backed by something in this repo the audience
  can clone and run.
- Demos that cannot fail live on conference wifi.

## Non-goals

- Building a full cloud-services replacement suite before the talk. One or
  two real self-hosted apps (spec 0007's `applications/apps/`) are enough to
  make the GitOps payoff concrete; the abstract will be revised to match.

## Design

### Revised abstract

`abstract.md` MUST be reframed from "escape cloud services" to "from blank
hardware to a self-healing Kubernetes platform, entirely from one git repo",
keeping the privacy/cost hook as motivation and dropping the Workspace/Dropbox
replacement promise. If one or two real self-hosted apps exist by the talk (see
open questions), add them as a closing example rather than restoring the
original framing.

### Outline and timing budget (~75 min content)

| # | Section | Time | Repo anchor |
|---|---------|------|-------------|
| 1 | Why a homelab in 2026 — cost, privacy, learning | 8 min | abstract themes |
| 2 | The stack at a glance — one diagram, layer by layer | 7 min | architecture doc |
| 3 | Bare metal → Proxmox: unattended install USB | 8 min | `playbooks/bootstrap/`, `infrastructure/linux/proxmox/` |
| 4 | Proxmox cluster + Ceph in one command | 10 min | `site.yml`; **demo A** |
| 5 | Talos: a Kubernetes OS with no shell | 12 min | spec 0013; the machine-config model, no SSH, API-driven upgrades; **demo D** |
| 6 | GitOps: the cluster that rebuilds itself | 15 min | specs 0007–0009; **demos B & C** |
| 7 | Keeping it alive: Renovate, upgrades, lessons learned | 10 min | renovate.json |
| 8 | Getting started yourself — minimal hardware, first steps | 5 min | root README |
|   | Q&A buffer | 15 min | |

### Demo plan — nothing depends on venue network

- **Demo A (recorded, time-lapse):** `site.yml` from blank Proxmox nodes to
  Ceph `HEALTH_OK`. Too slow and too risky live; a 90-second time-lapse
  with narration lands better.
- **Demo B (live, local):** GitOps loop against a pre-staged cluster —
  `git commit` a change to an app manifest, watch Flux reconcile it. Flux has
  no bundled UI, so the visual is the dashboard from spec
  [0009](0009-platform-services.md) alongside `flux events` in a terminal —
  rehearse this framing, since a CLI reconcile reads as less dramatic than an
  application tree turning green.
  Runs on a laptop-reachable homelab via VPN *with a recorded fallback*, or
  entirely on a local [kind](https://kind.sigs.k8s.io/) /
  [Talos-in-Docker](https://www.talos.dev/latest/talos-guides/install/local-platforms/docker/)
  cluster mirroring the repo.
- **Demo C (recorded):** the resilience money-shot — `remove-vms.yml`, full
  re-provision, Flux restores every workload. Time-lapse from spec 0007's
  rebuild acceptance test.
- **Demo D (recorded, time-lapse):** the in-place Talos OS upgrade.
  `upgrade.yml` rolling the whole cluster to a new Talos release — control
  planes one at a time, workers drained and upgraded — with workloads and
  Flux staying green throughout (spec
  [0013](0013-talos-cluster-lifecycle.md), TALOS-09). The thesis in one
  screen: there is no SSH, no package manager, and no shell in this segment —
  the OS is upgraded the way a deployment is rolled. It shares its narrative
  with demo C, so the two can be introduced together and buy back time for
  Q&A.
- The combined Grafana homelab dashboard (spec 0009) as the persistent
  backdrop/screensaver slide.

### Materials to produce

```
docs/presentation/
├── abstract.md        # revised per above
├── outline.md         # the table above, expanded with speaker notes
├── demos/
│   ├── README.md      # per-demo runbook: setup, script, fallback
│   └── recordings/    # gitignored or LFS — link from README if too large
└── slides/            # deck source (marp/reveal.js so it lives in git,
                       #  keeping with the everything-in-git theme)
```

### Dry runs

Two full timed rehearsals: one self-recorded, one with an audience of at
least one person unfamiliar with homelabs (proxy for the target audience).
Timing adjustments recorded in outline.md.

## Implementation plan

1. Revise abstract.md; write outline.md with speaker notes (both can start now —
   sections 1–5 don't depend on the GitOps specs).
2. Build slides skeleton; pick [Marp](https://marp.app/) or
   [reveal.js](https://revealjs.com/).
3. Record demo A during the next infrastructure rebuild.
4. After specs 0007–0009 land: stage demo B, record demo C.
5. Dry runs; final timing pass.

## Acceptance criteria

- [ ] outline.md exists with per-section speaker notes and timings summing
      to ≤ 78 minutes.
- [ ] All three demos have runbooks and offline fallbacks; B has been
      executed start-to-finish on the presentation laptop.
- [ ] Abstract makes no claim the repo can't demonstrate.
- [ ] One full dry run completed within time budget, feedback incorporated.

## Open questions

- Meetup date — sets the deadline for specs 0007–0009 and the second dry
  run; work backward once known.
- Whether one "real" self-hosted app (e.g. a photo or file service) should
  headline demo B to make the payoff tangible for non-infra developers.
