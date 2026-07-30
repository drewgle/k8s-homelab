# 0010 — Node OS evaluation: distro as a node property

**Status:** Draft
**Serves goals:** Try Linux distributions and evaluate how they are managed
over time; presentation
**Depends on:** [0019](0019-single-cluster-mixed-distro.md) (one cluster, per-node
distros — this spec's method rests on it)

## Context

The repo has always contained a *mechanism* for comparing node operating systems
([Talos Linux](https://www.talos.dev/) and
[Flatcar Container Linux](https://www.flatcar.org/)) but no *evaluation*: no
criteria, no recorded observations, no conclusion a reader could act on.
"Evaluate how they are managed over time" needs a written artifact that
accumulates over months, not an impression held in one person's head. That part
has not changed.

What changed is the mechanism, and it is worth being blunt about why. This spec
previously called for parallel `talos/` and `flatcar/` playbook trees producing two
isolated clusters on the same VLAN with disjoint addressing, run concurrently.
That comparison was never possible: two stacks want 72 GB against 48 GB of
physical RAM, and this spec's own implementation plan conceded in advance that it
would "fall back to alternating cycles and record that the comparison is
serialized". It also compared two clusters that each had their own copy of Flux,
Cilium, MetalLB and the Gateway — so a difference observed between them could have
come from the operating system or from whichever platform copy had drifted.

Spec [0019](0019-single-cluster-mixed-distro.md) replaced that with **one cluster
whose workers each declare a distro**. This spec is rewritten against it. The
comparison is now between nodes inside one running platform, which is both cheaper
and better controlled — with one real loss, recorded honestly below.

## Goals

- A criteria-driven comparison document that a homelab newcomer could use to
  pick a node OS.
- A dated journal capturing day-2 operations as they actually happen
  (upgrades, incidents, debugging sessions, distro swaps), because "over time" is
  the point.
- A comparison that measures the operating systems rather than gaps in this
  repo's automation.
- Raw material for the presentation's "one cluster, two operating systems"
  section (spec [0011](0011-meetup-presentation.md)).

## Non-goals

- Evaluating additional distros right now
  ([k3OS](https://github.com/rancher/k3os) is dead — the repo is archived —
  and [Bottlerocket](https://github.com/bottlerocket-os/bottlerocket) is
  AWS-oriented). The *structure* must allow a third, and under 0019 MIX-18 that
  costs a directory and a `distro.yaml` rather than a parallel playbook tree, but
  none is planned.
- Performance benchmarking — differences that matter in a homelab are
  operational, not throughput.
- Comparing control-plane distros concurrently. That is structurally impossible
  here (see [What this method loses](#what-this-method-loses)).

## Design

### Documents

```
docs/evaluations/
├── README.md                # What is being evaluated and how to read it
├── talos-vs-flatcar.md      # Criteria matrix + running conclusion
└── journal.md               # Dated, append-only observations
```

### The matrix is split in two, and the split is the method

Every criterion is either observable on a node inside the running cluster, or only
observable while a distro holds the control plane. Mixing them is how a
comparison ends up measuring the wrong thing.

**Node-level criteria — compared concurrently**, on one cluster, under the same
workloads, at the same instant:

| Criterion | What it measures |
|-----------|------------------|
| Node provisioning effort | Playbook complexity, boot-to-`Ready` time, failure modes during provision and join |
| OS upgrade experience | Steps, duration, failure recovery (`talos/upgrade.yml` vs `flatcar/update.yml`) on a node carrying real workloads |
| Automatic updates | Unattended update story (Flatcar [update_engine groups](https://www.flatcar.org/docs/latest/setup/releases/update-strategies/) vs Talos plus the Renovate soak policy) |
| Debuggability | What it takes to answer "why is this node unhealthy" with no SSH (Talos) versus SSH (Flatcar) |
| Configuration model | [Machine config API](https://www.talos.dev/latest/reference/configuration/) versus [Ignition](https://coreos.github.io/ignition/)/cloud-init; drift behavior after manual changes |
| **Workload compatibility** | Do our actual pods run? Seccomp defaults, read-only rootfs, kernel modules — observed on identical pod specs on the same cluster at the same time |
| **Swap cost** | Wall-clock time and operator steps to move one node to this distro (0019 MIX-23), and what went wrong on the way |
| **Contract onboarding cost** | What it took for this distro to satisfy 0019 MIX-17 and MIX-18 — the number that generalizes to distro number three |
| Security posture | Attack surface, patch latency, defaults |
| Automation fit | Fit with Ansible, Renovate and GitOps; version pinning in `versions.yaml` |
| Ecosystem and docs | Upstream docs quality, community, issue turnaround |

**Control-plane-level criteria — compared serially**, by alternating
`control_plane_distro` and rebuilding:

| Criterion | What it measures |
|-----------|------------------|
| Cluster bootstrap effort | `talosctl gen`/`apply`/`bootstrap` versus `kubeadm init` plus PKI pre-seeding |
| Control-plane HA | The VIP mechanism: one Talos config stanza versus kube-vip plus its `super-admin.conf` bootstrap workaround (spec 0016) |
| etcd operations | Snapshot, restore, member removal, and what a lost control plane costs |
| At-rest encryption | Talos's secretbox provider versus kubeadm's absence of one — and the fact that this asymmetry is what makes a control-plane distro change a rebuild rather than a swap (0019 MIX-14) |
| Cluster upgrade | Moving the whole cluster's Kubernetes version |

The three bolded node-level criteria are new, and the old method could not have
produced any of them. Swap cost and contract onboarding cost only exist because
swapping is now an operation. Workload compatibility needs both distros running
the same pod specs at the same moment, which needs one cluster.

### Journal

Append-only entries: date, distro, which nodes were running which distro at the
time, what was done or what happened, what it revealed. Every upgrade playbook
run, every distro swap, every incident, every "that was surprisingly hard or easy"
moment gets two to five sentences. The matrix cites journal entries as evidence.

Recording the cluster's distro layout in each entry is not bookkeeping for its own
sake — it is the mitigation for this method's main risk. A mixed cluster produces
oddities that are easy to blame on a distro when the real cause was the mix, and
without the layout written down an entry cannot be re-examined later.

### Parity work

Mostly dissolved, and this is the clearest single improvement over the old
method. Flatcar's missing `health-check.yml` and `add-node.yml` were asymmetries in
*this repo's automation*, not in the operating systems, and they were skewing the
comparison. Under 0019 MIX-18 there is one distro-neutral health check and one
node-add play that read each distro's `distro.yaml`, so the asymmetry cannot
exist — better than building two more playbooks to cancel it out.

What remains:

- Each distro must have a `distro.yaml` and satisfy the join contract (0019
  MIX-17, MIX-18). Whatever that costs is itself the *contract onboarding cost*
  criterion, so it is measurement, not overhead.
- Specs 0007–0009 must be deployed on the cluster before the "swap a node's OS
  under the same app layer" claim is made in the talk. This is now one deployment
  rather than two, and the claim is directly testable.

### Cadence

- Journal: written at the moment something happens (cheap, unstructured).
- Matrix: revisited after each meaningful event — upgrade cycle, incident, node
  swap, control-plane rebuild — and at minimum monthly until the presentation,
  then quarterly.
- A "current recommendation" paragraph at the top of `talos-vs-flatcar.md` is kept
  honest. It may say "too early to call" but must exist.

## What this method loses

Better on the axes this spec cares about, worse on one, and the honest version is
worth writing down rather than claiming a clean win.

**Better.** The plumbing confound is eliminated rather than reduced: same control
plane, same PKI, same Cilium release, same Flux tree, same workloads, same
instant. Spec 0016 claimed Cilium removed the CNI confound; one cluster removes
all the others. It fits in 48 GB, so the concurrent comparison this spec always
wanted can actually happen. And the day-2 data is richer, because both operating
systems face real workloads instead of a duplicate copy of them — spec
[0017](0017-self-hosted-forge.md)'s rootless DinD runners are a finding waiting to
happen.

**Worse.** The control-plane story can no longer be compared concurrently.
kube-vip's `super-admin.conf` bootstrap hack, etcd behavior, HA failover — these
only surface while that distro holds the control plane, so they must be compared
by alternating `control_plane_distro`, which is a rebuild and, if 0019's open
question 8 confirms the at-rest encryption divergence, a full restore each time.
This is the one place the two-cluster model was genuinely superior, and it is why
the matrix above is split rather than merged. Whole-cluster lifecycle events —
cluster upgrade, full rebuild — cannot be A/B'd at all.

**Risk to manage.** Mixed-cluster oddities misattributed to a distro. Mitigated by
the split matrix and by the journal convention of recording the distro layout at
the time of each entry.

## Implementation plan

1. Create the three documents with the split matrix skeleton, and seed the
   journal retroactively from git history (the initial provisioning experience of
   both distros is partially reconstructable from commit messages).
2. Bring up one cluster with mixed worker distros per 0019, and journal the first
   swap in each direction as it happens.
3. Run at least one OS upgrade cycle per distro on nodes carrying real workloads,
   journaling as things happen.
4. Run one control-plane rebuild with `control_plane_distro` alternated, and
   record what the rebuild actually cost — that number is the price of the serial
   half of the matrix.
5. Add a "Node OS evaluation" row to the root README documentation table.

## Acceptance criteria

- [ ] The matrix has a non-empty justification for every cell, each citing at
      least one journal entry, and node-level and control-plane-level criteria are
      not mixed.
- [ ] The journal shows entries spanning at least two months, at least one
      upgrade of each distro, and at least one swap in each direction.
- [ ] Every journal entry records which nodes were running which distro at the
      time.
- [ ] At least one cell in the *workload compatibility* row cites an observation
      of identical pod specs behaving differently per node — or states positively
      that none was found, which is also a result.
- [ ] The GitOps app layer has been reconciled onto the cluster, a worker's distro
      has been swapped underneath it, and every workload stayed up (ties to spec
      0007's rebuild criterion and 0019 MIX-23).
- [ ] The control-plane half of the matrix names the rebuild cost it was measured
      at, so a reader knows the comparison was serial and what that cost.
- [ ] The "current recommendation" paragraph exists and a newcomer can act on it.
