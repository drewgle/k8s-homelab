# NNNN — Short title

**Serves goals:** Which repo goals (see [README](README.md)) this serves, and
how — e.g. `Learning (k8s, Talos); repo organization`
**Depends on:** Specs that must land first, as links —
`[0007 GitOps bootstrap](0007-gitops-bootstrap.md)`. Omit the line if none.
**Affects:** Existing specs whose behavior this changes, as links, with a
short parenthetical saying what changes. Omit the line if none.
**Planned files:** The paths this spec creates or owns. A new spec may not
know them yet; fill them in as the design settles.

<!--
How to use this template:

- Copy to `NNNN-short-title.md` with the next free number, delete these
  comments, and replace each section's placeholder prose.
- A young spec leans on Goals / Non-goals / Design / Open questions. As the
  design settles it hardens into numbered Requirements, and the sections
  marked (early) are folded into them or deleted. Sections marked (optional)
  are kept only when they earn their place — an empty heading is clutter.
- Specs record the *current* plan. Rejected alternatives get a short "what
  was rejected and why" note where the decision is made, not a preserved
  draft; git history keeps old plans.
-->

## Context

Why this work exists: the gap between what the repo has and what it needs,
and where this spec's subject sits in the stack. Name the specs it builds on
and the spec that picks up where this one ends. A reader should understand
the problem before seeing any solution.

## Goals *(early)*

What this spec commits to delivering, as short bullets. These become the
seeds of Requirements and Acceptance criteria as the design settles.

## Non-goals *(early)*

What is deliberately out of scope, so nobody re-litigates it later. Say
where the excluded concern lives instead, if anywhere.

## Decision *(optional)*

For specs whose core is one consequential choice (a CNI, a storage backend):
state the choice in one sentence, then the options considered — a small table
works — and why the winner wins *for this repo's goals*.

## Requirements *(settled)*

Numbered, testable statements of intended behavior, each carrying a stable
ID with a short uppercase prefix unique to this spec (`VMP-`, `CNI-`,
`FORGE-`, ...):

- **PREFIX-01** Use MUST / MUST NOT for the invariant, then one or two
  sentences of *why* — the consequence of violating it — so the requirement
  survives contact with a reader who wants to change it.
- **PREFIX-02** IDs are stable once anything cites them: append new ones,
  never renumber or reuse (see [README](README.md) conventions).

## Design

How the requirements are met: the moving parts, what runs where, the order
things happen in. Keep rationale next to the design it justifies. Early on
this is the bulk of the spec; once requirements exist, keep only the
design detail that the requirements don't already pin down.

## Interfaces *(optional)*

What this spec consumes and produces across its boundary: variables read
from `vars.yml`, inventory groups, files written, contracts other specs
depend on. One "Consumes:" and one "Produces:" paragraph is usually enough.

## Implementation plan *(optional)*

The build order, as a short numbered list. Useful when the work spans
multiple changes or the ordering is load-bearing; skip it for one-shot work.

## Acceptance criteria

Concrete checks that make "done" testable — commands to run and what they
must show. Reference requirement IDs where a criterion verifies one:

- [ ] `some command` succeeds and shows X (PREFIX-01).
- [ ] Re-running the playbook reports zero changes.

## Known limitations *(optional)*

Sharp edges accepted on purpose: what does not work, when it bites, and the
precondition for lifting it. This is the section that saves the next person
a debugging session.

## Open questions *(early)*

Decisions deferred to implementation, each with the options and what would
decide between them. A settled spec should have few or none — resolve a
question by folding the answer into Requirements or Design and striking it
here (`~~question~~ **Decided: X** — see ...`).
