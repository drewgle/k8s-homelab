# 0010 — Node OS evaluation: Talos vs Flatcar

**Status:** Draft
**Serves goals:** Try Linux distributions and evaluate how they are managed
over time; presentation

## Context

The repo already contains the *mechanism* for comparing node operating
systems — parallel `talos/` and `flatcar/` playbook trees sharing the same
vars, network, and IP ranges, with `remove-vms.yml` to swap between them —
but no *evaluation*: no criteria, no recorded observations, no conclusion a
reader could act on. "Evaluate how they are managed over time" needs a
written artifact that accumulates over months, not an impression held in
one person's head.

## Goals

- A criteria-driven comparison document that a homelab newcomer could use to
  pick a node OS.
- A dated journal capturing day-2 operations as they actually happen
  (upgrades, incidents, debugging sessions), because "over time" is the
  point.
- Feature parity between the two playbook trees, so the comparison measures
  the operating systems rather than gaps in this repo's automation.
- Raw material for the "two OSes, one cluster spec" section of the
  presentation (spec [0011](0011-meetup-presentation.md)).

## Non-goals

- Evaluating additional distros (k3OS is dead, Bottlerocket is
  AWS-oriented). The *structure* should allow a third tree, but none is
  planned.
- Performance benchmarking — differences that matter in a homelab are
  operational, not throughput.

## Design

### Documents

```
docs/evaluations/
├── README.md                # What is being evaluated and how to read it
├── talos-vs-flatcar.md      # Criteria matrix + running conclusion
└── journal.md               # Dated, append-only observations
```

### Criteria matrix

Scored per OS with a short justification each, updated as experience
accumulates:

| Criterion | What it measures |
|-----------|------------------|
| Provisioning effort | Playbook complexity, boot-to-cluster time, failure modes during 01/02 playbooks |
| Upgrade experience | OS + Kubernetes upgrades: steps, duration, failure recovery (`talos/upgrade.yml` vs `flatcar/update.yml`) |
| Automatic updates | Unattended update story (Flatcar update_engine groups vs Talos + Renovate soak policy) |
| Debuggability | What it takes to answer "why is this node unhealthy" with no SSH (Talos) vs SSH (Flatcar) |
| Configuration model | Machine config API vs Ignition/cloud-init; drift behavior after manual changes |
| Ecosystem & docs | Upstream docs quality, community, issue turnaround |
| Security posture | Attack surface, patch latency, defaults |
| Automation fit | How well each fits Ansible + Renovate + GitOps (e.g. version pinning in `versions.yaml`) |

### Journal

Append-only entries: date, OS, what was done or what happened, what it
revealed. Every run of an upgrade playbook, every incident, every "that was
surprisingly hard/easy" moment gets two to five sentences. The matrix cites
journal entries as evidence.

### Parity work

Differences in the playbook trees that would skew the comparison:

- Flatcar has no `health-check.yml`; Talos does. Add one.
- Talos has `add-node.yml`; Flatcar does not. Add one, or record the
  asymmetry as a finding (kubeadm join vs machine-config apply is itself an
  evaluation data point — decide which and write it down).
- Both trees must complete specs 0007–0009 (GitOps bootstrap runs
  identically) before the "swap OS under the same app layer" claim is made
  in the talk.

### Cadence

- Journal: written at the moment something happens (cheap, unstructured).
- Matrix: revisited after each meaningful event (upgrade cycle, incident,
  OS swap) and at minimum monthly until the presentation, then quarterly.
- A "current recommendation" paragraph at the top of `talos-vs-flatcar.md`
  is kept honest — it may say "too early to call" but must exist.

## Implementation plan

1. Create the three documents with the matrix skeleton and seed the journal
   retroactively from git history (initial provisioning experience of both
   trees is already partially reconstructable from commit messages).
2. Parity: Flatcar `health-check.yml`, decision on `add-node.yml`.
3. Run one full swap cycle (Talos → Flatcar → Talos) with specs 0007–0009
   deployed, journaling each leg.
4. Add a "Node OS evaluation" row to the root README documentation table.

## Acceptance criteria

- [ ] The matrix has a non-empty justification for every cell, each citing
      at least one journal entry.
- [ ] The journal shows entries spanning at least two months and at least
      one upgrade of each OS.
- [ ] A full OS swap under the GitOps app layer has been performed and
      journaled, and every workload returned (ties to spec 0007's rebuild
      criterion).
- [ ] The "current recommendation" paragraph exists and a newcomer can act
      on it.
