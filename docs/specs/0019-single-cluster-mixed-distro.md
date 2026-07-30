# 0019 — One cluster, per-node Linux distributions

**Status:** Draft
**Serves goals:** Distro evaluation; learning (k8s, Talos, kubeadm, PKI);
repo organization; presentation
**Depends on:** [0006](0006-vm-platform.md) (the VM layer this re-shapes),
[0013](0013-talos-cluster-lifecycle.md),
[0014](0014-flatcar-cluster-lifecycle.md) (both become implementations of one
join contract)
**Supersedes requirements:** 0006 VMP-04, VMP-07; 0013 TALOS-01; 0014 FLAT-06;
0016 CNI-01, CNI-05, CNI-06 — see [Requirement supersession](#requirement-supersession)
**Affects:** [0007](0007-gitops-bootstrap.md) (one kubeconfig, one cluster),
[0008](0008-kubernetes-storage.md) (the OS-swap volume question becomes a
supported operation), [0009](0009-platform-services.md) (address plan),
[0010](0010-node-os-evaluation.md) (its entire method),
[0011](0011-meetup-presentation.md) (section 5),
[0015](0015-backup-and-recovery.md) (identity material, etcd symmetry),
[0016](0016-cluster-networking-cilium.md) (one Cilium release),
[0017](0017-self-hosted-forge.md) (FORGE-13/FORGE-14 become implementable; the
address open question closes)

Requirement prefix is `MIX-`. `CLU-` was rejected because 0013, 0014 and 0016
are all "about the cluster" and it would read as a general bucket; `NODE-` reads
as a sibling of 0002's `INIT-`. `MIX-` names the actual subject and greps
cleanly.

## Context

The repo models Talos and Flatcar as two isolated clusters on the same VLAN with
disjoint addressing, and 0006's VMP-07 makes non-collision an invariant so both
can run at once.

That model has never run, and cannot. 0006's own capacity note records that two
stacks want 72 GB against 48 GB of physical RAM. So the side-by-side comparison
spec 0010 depends on has never happened, and everything built above the cluster —
Flux (0007), MetalLB and the shared Gateway (0009), the forge (0017) — silently
exists in exactly one of the two clusters, making the other permanently
second-class. Two clusters reconciling the single flat `applications/` tree on one
VLAN would both claim the same LoadBalancer addresses. The "evaluate distros over
time" goal was being served by a mechanism that does not fit in the hardware and
by a platform nobody would maintain twice.

Writing spec 0017 is what surfaced this. FORGE-14 pins CI runners to Flatcar
worker nodes with a `nodeSelector` and FORGE-13 denies runner egress to the Talos
API ports — both statements are only meaningful inside a single cluster
containing both. Those requirements are not mistakes; they are the first ones
written against the model actually wanted, and they read as contradictions only
because the layers below them describe a different topology.

This spec replaces the two-cluster model with **one cluster whose workers each
declare their own Linux distribution**. Swapping a worker from Talos to Flatcar,
or to a distro tried for the first time next year, destroys and re-provisions one
VM and rejoins the same cluster with the same name, address, role and volumes.
The distro comparison stops being two parallel universes and becomes an
observable property of nodes inside the platform that is actually running.

Two things make this possible, and both are decisions rather than conveniences.
First, cluster identity moves out of any distro: one PKI bundle, committed
SOPS-encrypted, from which Talos's `secrets.yaml` is *rendered* and kubeadm's
`/etc/kubernetes/pki` is *pre-seeded*. Second, "joining" is defined as a contract
at the kubelet — CA certificate, bootstrap credential, API endpoint — of which
`talosctl apply-config` and `kubeadm join` are two implementations rather than two
clusters.

## Decision

**One Kubernetes cluster. Every worker independently declares its distro and can
be swapped in place. All control-plane nodes run one distro, named by
`control_plane_distro`, defaulting to `talos`.** Cluster identity is a
distro-neutral PKI bundle in the repository. Mixed-distro control planes and
mixed etcd are out of scope.

### Options considered

| Option | Fits 48 GB | Distro evaluation | Verdict |
|--------|-----------|-------------------|---------|
| **One cluster, per-node distro** (chosen) | yes, 36 GB | continuous, same workloads at the same instant | The comparison measures the OS because everything else is literally shared |
| Two clusters, disjoint addressing (status quo, VMP-07) | **no**, 72 GB | never actually ran | Also duplicates Flux, Cilium, MetalLB, the Gateway and the forge, and 0017's forge can only live in one of them |
| One cluster, one distro, rebuild to switch | yes | serialized, destroys day-2 history | An OS comparison whose method is "delete the evidence and start again" |
| Mixed control plane, mixed etcd | yes | richest | **Rejected, out of scope.** etcd member parity, divergent static-pod layout and divergent at-rest encryption providers put the failure surface on quorum — the one thing you cannot debug under time pressure |
| Two clusters plus [Cilium Cluster Mesh](https://docs.cilium.io/en/stable/network/clustermesh/clustermesh/) or Cluster API | no | good | Footprint, and multi-cluster is 0007's stated non-goal |
| A management plane ([Talos Omni](https://www.siderolabs.com/platform/saas-for-kubernetes/), CAPI providers) | marginal | good | Hides exactly the plumbing this repo exists to learn, and adds a dependency above the cluster it manages |
| Keep per-distro PKI, trust both CAs on one API server | yes | n/a | Multiple client CAs are possible; one service-account signing key and one etcd CA are not optional. Identity is singular or it is not identity |
| Hold the bundle only in the Ansible Vault file, uncommitted | yes | n/a | Contradicts 0007's "secrets live in git, encrypted", and rendering needs it readable at play time — which is what SOPS gives |

## Requirements

### Cluster identity

- **MIX-01** There is exactly **one** Kubernetes cluster: one `cluster_name`, one
  pod CIDR, one service CIDR, one cluster DNS address, one DNS domain, one API
  endpoint. The `talos_*` and `flatcar_*` cluster variables are replaced by
  `cluster_*` equivalents. A distro-scoped variable MUST only describe *how a
  node is built* — image, installer, install disk, update channel — never *what
  cluster it joins*.
- **MIX-02** Cluster identity is one bundle at
  `infrastructure/linux/cluster/pki/`, committed and **SOPS-encrypted** (0007's
  `.sops.yaml` rules extend to cover it), in two files:
  - `cluster.yaml` — the Kubernetes CA certificate and key, the etcd CA
    certificate and key, the front-proxy (aggregator) CA certificate and key, the
    service-account signing key pair, and the cluster bootstrap token.
  - `talos-machine.yaml` — material that must also be stable but is **not**
    cluster identity: the Talos OS CA, the trustd token, `cluster.id`,
    `cluster.secret`, and the secretbox encryption secret.

  The split is load-bearing. A valid Talos `secrets.yaml` cannot be produced from
  distro-neutral material alone, and folding Talos-only secrets into the neutral
  file would hand a future distro fields it cannot use and cannot explain.
- **MIX-03** The bundle is generated **once**, by
  `playbooks/kubernetes/00-cluster-pki.yml`, under a `creates:` guard, and MUST
  NOT be regenerated by a re-run. Regenerating it against a live cluster orphans
  that cluster permanently. This is TALOS-01's rule, relocated to where it now
  belongs.
- **MIX-04** No distro owns identity. Every per-distro identity artifact is
  **derived, reproducible and gitignored**: Talos's `secrets.yaml` and machine
  configs are rendered from the bundle; kubeadm's `/etc/kubernetes/pki` is
  **pre-seeded from the bundle before `kubeadm init`**, so kubeadm adopts the
  existing CA rather than creating one. Losing a derived artifact costs a
  re-render. Losing the bundle means a new cluster.
- **MIX-05** CA **private** keys MUST reach control-plane nodes only. A worker's
  join material is exactly three things: the Kubernetes CA *certificate*, a
  bootstrap credential, and the API endpoint. Any provisioning path that would
  place a CA key on a worker is a defect, not a shortcut.

  This is a change, not a restatement. As drafted for spec
  [0013](0013-talos-cluster-lifecycle.md),
  `infrastructure/linux/talos/templates/worker.yaml.j2` would ship
  `cluster.ca.key` — the Kubernetes CA private key — to every worker, and the
  Talos OS CA key via `machine.ca.key`. Both are closed by this requirement.
- **MIX-06** The bootstrap token's *value* is stable — it lives in the bundle,
  and a Talos machine config persists it on disk — while its *server-side
  validity* is transient. Every provisioning or join run MUST ensure a matching
  `bootstrap-token-<id>` Secret exists in `kube-system` with a bounded TTL
  covering the join window, and MUST NOT extend it afterwards. Stable value,
  transient validity: this is what reconciles Talos's baked-in `cluster.token`
  with 0014's FLAT-04, where tokens are short-lived by design.
- **MIX-07** The bundle is the one artifact whose loss means rebuilding the
  cluster. It is covered by spec 0015 section 1, and because it is committed
  encrypted, the out-of-band secret protecting it is the same age key and Ansible
  Vault password that already protect everything else — one secret, not three.

### Naming, addressing, capacity

- **MIX-08** Node identity is distro-neutral and stable across a swap.

  **Stable:** the inventory hostname, the OS hostname and the Kubernetes Node
  name (all three MUST be the same string); the node IP; `vm_id`; the Proxmox
  host it runs on; the role; every authoritative label except the distro label;
  and any bound PersistentVolumes.

  **Changes:** the OS image; the provisioning artifact (machine config versus
  Ignition); the management transport (`talosctl` on 50000/tcp versus SSH on
  22/tcp); `ansible_connection` and `ansible_user`; the readiness port; the
  kubelet's provenance; the OS-update mechanism; and the distro label.

  A swap that changes anything in the first list is not a swap.
- **MIX-09** One authoritative address plan on `192.168.100.0/24` (VLAN 100),
  replacing VMP-07's two disjoint ranges:

  | Range | Purpose |
  |-------|---------|
  | `.1` | Gateway |
  | `.200` | **The** control-plane VIP (`cluster_vip`) |
  | `.201–.210` | Control-plane nodes — `k8s-cp-NN` is `.200 + NN` |
  | `.211–.239` | Worker nodes — `k8s-worker-NN` is `.210 + NN` |
  | `.240–.250` | MetalLB pool (spec 0009); `.240` shared Gateway, `.241` Forgejo SSH (0017 FORGE-07) |
  | `.251–.254` | Reserved for MetalLB pool growth, nothing else |

  `.220`, the retired Flatcar VIP, returns to the worker range. This **closes the
  blocking open question in spec 0017** — three documents previously carried
  three incompatible address models, and there is no longer a VIP carve-out to
  reconcile. The documents that MUST be corrected in the same change:
  `infrastructure/linux/talos/NETWORK.md` (which claims `.211-.250` for workers
  and reserves `.251-.254` for load balancers, and which MUST also **move to
  `infrastructure/linux/cluster/NETWORK.md`**, because nothing in it is
  Talos-specific), 0006 VMP-07, 0009's MetalLB pool text, 0016 CNI-09, 0017,
  `vars.yml.example`, `inventory.yaml`, the root `README.md`, and
  `docs/architecture/README.md`.
- **MIX-10** `vm_id` MUST equal the final octet of the node's `ansible_host` and
  MUST NOT encode the distro. VMP-04's "Talos uses 2xx, Flatcar 3xx" is
  superseded. The Talos 2xx IDs coincide with those nodes' final octets and
  survive unchanged; the Flatcar 3xx IDs disappear. One number identifies the VM,
  the address and the node.
- **MIX-11** Node addressing MUST be static and MUST come from inventory.
  Addresses appear in `certSANs` and in etcd's advertised subnets, so an address
  that changes across a swap invalidates that node's PKI. 0013's machine-config
  templates fall back to `dhcp: true` when `kubernetes_network_interface` is
  unset — under this requirement that fallback is a defect and the variable is
  required, not optional.
- **MIX-12** Capacity envelope, replacing 0006's 72 GB note: 3 × 4 GB control
  planes plus 3 × 8 GB workers is **36 GB of 48 GB physical**, with one control
  plane and one worker per Proxmox host — 12 GB of each 16 GB host, leaving
  roughly 3.5–4 GB per host for PVE and Ceph.

  An **in-place** swap (destroy the slot, re-provision the same slot) needs
  **zero** additional RAM, which is why MIX-23 makes it the default rather than
  add-then-remove: a host already carrying 12 GB has no room for a temporary 8 GB
  worker. The cost of in-place is running at N-1 workers for the duration, so
  **the sum of workload requests MUST fit on two workers** — an acceptance
  criterion, not an aspiration.

  At current sizing a fourth 8 GB worker does **not** fit (44 GB); the honest
  options are 6 GB workers (3 × 4 + 4 × 6 = 36 GB) or more RAM. Spec 0017's "if a
  fourth worker appears" needs to say so.

### Distro declaration and roles

- **MIX-13** Inventory groups are **role-based**: `kubernetes_controlplane` and
  `kubernetes_worker`. Each host declares `node_distro`. Distro-scoped groups
  MUST be *computed* (`group_by key=distro_{{ node_distro }}`), never authored, so
  adding a distro adds no inventory group. Connection variables MUST be derived
  from `node_distro` rather than set per group, because `ansible_connection: local`
  (Talos) and `ansible_user: core` (Flatcar) are now per-host facts:

  ```yaml
  kubernetes_worker:
    hosts:
      k8s-worker-01: {ansible_host: 192.168.100.211, vm_id: 211, node_distro: talos,   proxmox_node: pve1}
      k8s-worker-02: {ansible_host: 192.168.100.212, vm_id: 212, node_distro: talos,   proxmox_node: pve2}
      k8s-worker-03: {ansible_host: 192.168.100.213, vm_id: 213, node_distro: flatcar, proxmox_node: pve3}
  ```

- **MIX-14** `control_plane_distro` (default `talos`) names the distro of **every**
  control-plane node. A control-plane host whose `node_distro` differs MUST fail
  validation. Changing `control_plane_distro` on an existing cluster is **not** a
  swap: at-rest encryption providers, static-pod layout and etcd data directories
  all differ, so it is a documented rebuild-and-restore (spec 0015), and the play
  MUST refuse to do it implicitly.
- **MIX-15** Two distro labels, deliberately:
  - `node.homelab/distro` — self-declared by the node's own labelling mechanism
    (Talos `machine.nodeLabels`, kubelet `--node-labels`). Informational and
    convenient.
  - `node-restriction.kubernetes.io/distro` — set from the control machine after
    join, and **authoritative**. The
    [`node-restriction.kubernetes.io/`](https://kubernetes.io/docs/reference/access-authn-authz/admission-controllers/#noderestriction)
    prefix is the one prefix a kubelet cannot set for itself, which is exactly the
    property needed here: spec 0017 treats CI runner pods as
    container-escape-adjacent and FORGE-14 pins them *away* from Talos, so if the
    label a `nodeSelector` trusts were kubelet-settable, a compromised node could
    relabel itself to attract the runners.

  The join play MUST verify the self-declared label matches the inventory
  declaration, and MUST set the authoritative one.

  **No standing distro taints.** Workloads are distro-agnostic by default and
  that is the point. A `distro=<x>:NoSchedule` taint remains the documented
  exception path, and is spec 0017's stated upgrade for CI isolation.
- **MIX-16** The swap play MUST refuse a swap that would leave **zero** nodes
  satisfying a distro `nodeSelector` that a deployed workload uses. With FORGE-14
  in place, swapping the last Flatcar worker to Talos leaves the Forgejo runners
  `Pending` forever — a failure mode this spec creates, so this spec closes it.

### The join contract

- **MIX-17** A node joins the cluster by satisfying five obligations. This is the
  contract; distros are implementations of it.
  1. The OS hostname equals the inventory hostname, so the Node name is stable
     across a swap.
  2. The node's IP is the inventory address, statically configured.
  3. The Kubernetes CA **certificate** from the bundle is present and trusted.
  4. A kubelet is configured to TLS-bootstrap against `cluster_endpoint` (the
     VIP) using the MIX-06 bootstrap credential, and to report `--node-ip` as the
     inventory address, `clusterDNS` as `cluster_dns`, and `clusterDomain` as
     `kubernetes_dns_domain`.
  5. A CRI socket exists and **no CNI is configured** — Cilium is a DaemonSet
     (0016 CNI-02, CNI-08), so a joining node is expected to be `NotReady` until
     the agent lands on it.

  Anything beyond this — `kubeadm join`'s discovery phases, Talos's machine-config
  apply — is an implementation detail of one distro, not a cluster requirement.
  This is what makes distro number three cheap.
- **MIX-18** A distro is an implementation of the contract, declared in one file
  so that adding a distro is additive and touches no generic play.
  `infrastructure/linux/<distro>/distro.yaml`:

  ```yaml
  name: flatcar
  supports_controlplane: true       # false for a distro only ever used on workers
  readiness_port: 22                # VMP-09, generalized
  connection: {ansible_connection: ssh, ansible_user: core}
  provision: playbooks/flatcar/01-provision-vms.yml
  join:      playbooks/flatcar/join-node.yml
  upgrade:   playbooks/flatcar/update.yml
  reset:     playbooks/flatcar/reset-node.yml   # may be a no-op: the VM is destroyed
  node_label_mechanism: kubelet-node-labels
  ```

  The generic plays — swap, remove-node, health-check, provision — MUST read this
  file and MUST NOT contain a distro name. A third distro is a directory plus
  templates.
- **MIX-19 (Talos worker, any control-plane distro)** A Talos worker joins by
  machine config carrying `cluster.ca.crt` (certificate only, per MIX-05),
  `cluster.token`, and `cluster.controlPlane.endpoint` set to the VIP — which is
  substantially what 0013's `worker.yaml.j2` is designed to do, so the mechanism
  needs no invention, only the CA-key removal. Its `machine.ca` certificate,
  `machine.token` and `cluster.id`/`cluster.secret` come from the bundle's Talos
  section. KubePrism stays enabled in the machine config, because Talos uses it
  internally and it costs nothing, but MUST NOT appear in Cilium's Helm values
  (see [One Cilium release](#one-cilium-release)). Subject to open question 2.
- **MIX-20 (kubeadm worker, any control-plane distro)** When
  `control_plane_distro` is kubeadm-based, the worker joins with
  `kubeadm join --token <bundle token> --discovery-token-ca-cert-hash sha256:<hash>`.

  When the control plane is **Talos** — the default configuration — kubeadm's
  discovery and config-fetch phases look for cluster artifacts a Talos control
  plane does not create: `kube-public/cluster-info`, `kube-system/kubeadm-config`
  and `kube-system/kubelet-config`. Two supported paths, in preference order:
  1. **kubeadm compatibility surface.** The cluster bootstrap applies those
     ConfigMaps plus their bootstrapper RBAC as a first-class committed artifact,
     and the worker joins with `kubeadm join --discovery-file <bootstrap-kubeconfig>`
     — file discovery avoids the anonymous `cluster-info` read entirely. Keeps one
     code path for kubeadm workers regardless of control-plane distro, and keeps
     kubeadm's learning value.
  2. **Raw kubelet bootstrap.** Write `bootstrap-kubelet.conf` from the bundle and
     let the kubelet bootstrap itself, with no `kubeadm join` at all. Satisfies
     MIX-17 directly and depends on no kubeadm-side artifacts.

  This spec MUST record which one is in use, because the failure signatures are
  completely different. Resolved by open question 1.
- **MIX-21** There is exactly **one** API endpoint: `cluster_vip`
  (`192.168.100.200:6443`), in every `certSAN`, every kubeconfig, and every
  kubelet's bootstrap config. Its **mechanism follows `control_plane_distro`** —
  Talos's etcd-elected `machine.network.interfaces[].vip.ip`, or kube-vip as a
  static pod with ARP and leader election. Exactly one mechanism MUST be active;
  two ARP claimants for one address is a flapping VIP, which presents as
  intermittent API failure and is miserable to diagnose. Workers MUST NOT run the
  VIP mechanism, and every join step MUST wait on the VIP before using it.
- **MIX-22** One `kubernetes.version`, in
  `infrastructure/linux/cluster/versions.yaml`. Per-distro `versions.yaml` files
  keep only OS and installer versions plus distro-specific components such as
  kube-vip. Today the Kubernetes version is duplicated in two files and matches by
  luck; in one cluster a mismatch is a real version-skew violation. The
  Talos-to-Kubernetes pairing constraint now bounds the whole cluster even when
  Talos runs only on workers.

### The swap operation

- **MIX-23** `playbooks/kubernetes/swap-node-distro.yml` performs, in order, for
  exactly one node: preflight (the node exists; it is a **worker**; the target
  distro implements the contract; the cluster is healthy; etcd is healthy; MIX-16
  is satisfied; PodDisruptionBudgets permit the drain) → record identity (name,
  IP, `vm_id`, `proxmox_node`, role, labels) → `cordon` → `drain
  --ignore-daemonsets --delete-emptydir-data` with a bounded timeout → assert no
  non-DaemonSet pods remain → assert volumes detached → **delete the Node object**
  → destroy the VM → re-provision the same slot with the new distro's
  provisioning path → join, registering cordoned so nothing schedules before
  Cilium is running there → wait for `Ready` **and** for the cilium-agent pod on
  that node → verify labels, `node_distro`, address and `vm_id` → `uncordon` →
  post-verify.

  The desired distro comes from inventory (`node_distro`); the play detects the
  actual distro from the authoritative label and acts only on a difference, so a
  re-run over a converged node changes nothing.
- **MIX-24** The swap MUST be idempotent and resumable: each phase guarded by
  observable state, so a re-run after a failure continues rather than restarting.
  A failure MUST leave the cluster in a *safe* state — the node cordoned, or
  absent — and MUST NOT leave a half-joined node behind a stale Node object.
- **MIX-25** The old Node object MUST be deleted **before** the replacement
  kubelet registers. A kubelet re-registering under an existing Node object does
  not remove labels it no longer sets, so skipping this leaves a Flatcar node
  still labelled `distro=talos` — the exact lie MIX-15 exists to prevent, and the
  exact input FORGE-14's `nodeSelector` trusts.
- **MIX-26** Removing any control-plane node MUST remove its etcd member first
  (`talosctl etcd remove-member`, or `kubeadm reset` plus `etcdctl member
  remove`). The swap play MUST refuse to run against a control-plane node at all:
  control-plane distro uniformity is MIX-14, so a control-plane change is a
  `control_plane_distro` change, which is a rebuild.
- **MIX-27** `remove-vms.yml` MUST NOT destroy a VM whose Node object still
  exists, unless `-e teardown=true` — whole-cluster teardown, where cluster-side
  eviction is pointless. Its `-e vm_type=<talos|flatcar>` selector is superseded
  by `-e nodes=[...]` or `-e teardown=true`.

  This closes a gap in 0006's VMP-08, which stops and `qm destroy --purge`es VMs
  with no drain and no Node deletion — leaving stale Node objects and, on control
  planes, stale etcd members that block quorum on the way back up.
- **MIX-28** A swap MUST re-create the VM on the **same Proxmox host**, with
  `proxmox_node` pinned from the recorded identity.
  [proxmox-csi-plugin](https://github.com/sergelogvinov/proxmox-csi-plugin) labels
  nodes by `topology.kubernetes.io/zone` set to the Proxmox node (spec 0008), so a
  slot that moves hosts strands its volumes. VMP-03's round-robin placement is for
  first provisioning only.

## Why identity leaves the distros

Both distros need the same cryptographic material; left to themselves they each
generate their own copy and call it the cluster. Making it one copy, generated
once and owned by neither, is the whole mechanism behind a seamless swap.

| Bundle field | Talos `secrets.yaml` path | kubeadm path |
|---|---|---|
| Kubernetes CA cert/key | `certs.k8s.crt` / `.key` | `/etc/kubernetes/pki/ca.{crt,key}` |
| etcd CA cert/key | `certs.etcd.crt` / `.key` | `/etc/kubernetes/pki/etcd/ca.{crt,key}` |
| Front-proxy CA cert/key | `certs.k8saggregator.crt` / `.key` | `/etc/kubernetes/pki/front-proxy-ca.{crt,key}` |
| Service-account key pair | `certs.k8sserviceaccount.key` | `/etc/kubernetes/pki/sa.{key,pub}` |
| Bootstrap token | `secrets.bootstraptoken` | `kubeadm token` / `bootstrap-token-<id>` Secret |
| Talos OS CA | `certs.os.crt` / `.key` | — |
| trustd token | `trustdinfo.token` | — |
| `cluster.id`, `cluster.secret` | `cluster.id`, `cluster.secret` | — |
| Secretbox encryption secret | `secrets.secretboxencryptionsecret` | — (no `EncryptionConfiguration` by default) |

The last four rows are why MIX-02 splits the bundle: they have no kubeadm
counterpart, and a future distro would inherit fields it cannot use.

The two bottom rows also explain MIX-14. Talos encrypts etcd at rest with
secretbox; kubeadm sets no `EncryptionConfiguration`. etcd data written under one
is not readable under the other, so a control-plane distro change is a restore,
not a swap. Confirming this is open question 8.

## The join contract, defined at the kubelet

MIX-17 deliberately stops at the kubelet rather than at a distro's tooling.
`kubeadm join` is sugar over TLS bootstrap: it discovers the API server, verifies
the CA against a hash, writes `bootstrap-kubelet.conf`, and lets the kubelet
request its own client certificate. Talos's `apply-config` does the same work from
a machine config. Naming the underlying obligations means a new distro implements
five things it can verify locally, instead of reverse-engineering whichever
distro happened to bootstrap the cluster.

The practical payoff is asymmetric and worth stating: the Talos side of the
contract is nearly free, because the worker machine config 0013 specifies carries
exactly the right fields. The kubeadm side needs a decision (MIX-20) because
kubeadm expects cluster-side artifacts that only kubeadm creates. That asymmetry
is itself spec 0010 material.

## One VIP, two mechanisms

There is one address, `192.168.100.200`, and whichever distro holds the
control plane holds it. The invariant that matters is **exactly one claimant**:
Talos's etcd-elected VIP and kube-vip must never both be configured, because two
ARP claimants for one address produce intermittent API failures that look like
everything except an addressing problem.

Because the VIP is a single point of failure for every client including the
playbooks that would repair it, the break-glass path must be written down rather
than rediscovered during an outage. The path is cheap: every control-plane
node's own address is in `certSANs` (0013, 0014), and the bundle is in git, so an
admin kubeconfig pointed straight at a node address works. Document that
procedure alongside MIX-21.

## The swap, step by step

MIX-23 lists the order. What matters for implementation is the state each phase
leaves behind, because that is what makes MIX-24's resumability real:

| Phase | Observable state on success | Safe to re-enter? |
|---|---|---|
| Preflight | nothing changed | yes |
| Record identity | facts cached | yes |
| Cordon | `SchedulingDisabled` | yes, idempotent |
| Drain | no non-DaemonSet pods on the node | yes, re-drains cleanly |
| Delete Node | Node object absent | yes, absence is the goal |
| Destroy VM | `vm_id` absent from `qm list` | yes, absence is the goal |
| Provision | VM answers on the distro's readiness port | yes, VMP-06 is idempotent |
| Join | Node present, `NotReady`, cordoned | needs care — a partial join must be detectable |
| Wait Ready | Node `Ready`, cilium-agent `Ready` | yes |
| Uncordon | schedulable, labels correct | yes |

Two phases deserve the attention: *Join* is the only one where a partial result
is not simply "absent or present", and *Delete Node* is the one whose omission
produces MIX-25's silent mislabelling rather than a visible failure.

### In place, not add-then-remove

Add-then-remove is the better procedure in the abstract — no capacity dip, and
the old node stays as a fallback until the new one is `Ready`. MIX-12's
arithmetic forbids it here: a Proxmox host already carrying a 4 GB control plane
and an 8 GB worker cannot also carry a temporary 8 GB worker, and MIX-28 pins the
replacement to that same host for volume topology. So the swap is in place, and
the cost is a documented N-1 window. If the workload set ever stops fitting on
two workers, the honest fix is more RAM, not a cleverer playbook.

## Heterogeneity is a new failure class

One cluster with different operating systems on different nodes means identical
pod specs can behave differently depending on where they land. Talos sets
`defaultRuntimeSeccompProfileEnabled: true` and has a read-only rootfs; Flatcar
does neither. Spec 0017's rootless DinD is the first known casualty, and FORGE-14
is already the mitigation.

This is deliberate, and it is spec 0010's richest new data source — it is the
only way to observe "does this distro run our actual workloads" without a second
copy of the platform. But it is genuinely a class of bug this repo has never had,
and it presents as "works on two of three workers", which reads as flakiness
rather than as a distro difference. Naming it here so that nobody is surprised is
part of the spec's job.

## Requirement supersession

Following the convention in [the specs README](README.md#requirement-supersession):

| Retired | Replaced by | Home of the replacement |
|---|---|---|
| 0006 VMP-04 | VMP-11 | 0006 — VM identity stays 0006's subject |
| 0006 VMP-07 | VMP-12, plus MIX-09 for the plan itself | 0006 and here |
| 0013 TALOS-01 | MIX-02, MIX-03, MIX-04 | here — the decision moved out of Talos |
| 0014 FLAT-06 | FLAT-10 | 0014 |
| 0016 CNI-01 | CNI-10 | 0016 — Cilium values stay 0016's subject |
| 0016 CNI-05 | CNI-11 | 0016 |
| 0016 CNI-06 | CNI-12 | 0016 |

Amended in place without new IDs, because intent survives and only stack-specific
wording changes: 0006 VMP-01, VMP-03, VMP-09; 0014 FLAT-02, FLAT-04, FLAT-09;
0016 CNI-04, CNI-09.

## One Cilium release

One cluster means one Helm release, and a single release cannot express a
per-node `k8sServiceHost`. CNI-05 is therefore not amendable — it is
unimplementable. This spec states the constraint; the replacement requirements
live in 0016, where Cilium's values belong.

The constraint: **every Helm value MUST be valid on every node distro in the
cluster simultaneously.** Checked value by value, four of the five values 0016
called Talos-specific are nothing of the kind — `ipam.mode=kubernetes` is a
cluster-wide choice, `cgroup.autoMount.enabled=false` and
`cgroup.hostRoot=/sys/fs/cgroup` are the standard recommendation for any host
with cgroup v2 already mounted (which Flatcar is), and the explicit
`securityContext.capabilities.*` lists match the chart's own defaults while
buying least privilege everywhere. Only `k8sServiceHost=localhost` with
`k8sServicePort=7445` is a genuine conflict, because KubePrism does not exist on
non-Talos nodes and the agent would dial a closed port there.

So CNI-06's premise is wrong in both directions: four values should be applied
cluster-wide, and the fifth cannot be applied anywhere. The resolution in 0016
CNI-11 is to point `k8sServiceHost` at `cluster_vip:6443` on every node, which
adds no new dependency — MIX-21 already makes the VIP the endpoint baked into the
PKI, every kubeconfig and every kubelet config.

## Implementation plan

1. `infrastructure/linux/cluster/` — bundle layout, `.sops.yaml` rules,
   `versions.yaml`, `NETWORK.md` moved out of `talos/`, and
   `playbooks/kubernetes/00-cluster-pki.yml` with the `creates:` guard.
2. Inventory and `vars.yml.example`: role-based groups, `node_distro`,
   `control_plane_distro`, `cluster_*` variables, `.220` retired, `vm_id` as the
   last octet.
3. Talos: render `secrets.yaml` and machine configs from the bundle; drop
   `cluster.ca.key` and `machine.ca.key` from the worker template (MIX-05); make
   bootstrap conditional on `control_plane_distro == talos`; add `join-node.yml`
   and `distro.yaml`.
4. kubeadm/Flatcar: pre-seed `/etc/kubernetes/pki` before `kubeadm init` and
   verify the resulting CA fingerprint; run kube-vip only when Flatcar holds the
   control plane; add a worker-only join path and `distro.yaml`.
5. MIX-20's chosen path — the kubeadm compatibility surface, or raw kubelet
   bootstrap — whichever open question 1 supports.
6. Cilium: one release, one value set, one version key.
7. `playbooks/kubernetes/`: `swap-node-distro.yml`, `remove-node.yml`, and a
   distro-neutral `health-check.yml` replacing the Talos-only one — which closes
   0014's parity gap by deletion rather than duplication.
8. `remove-vms.yml` guard rails (MIX-27).
9. Amend every affected spec and document in the same change as the code that
   makes it true, and keep requirement citations in playbook comments pointed at
   live IDs rather than the ones this spec retires:
   - `CNI-05` and `CNI-06` in the Cilium install steps of both bootstrap
     playbooks. The "Flatcar has no KubePrism equivalent" reasoning behind
     CNI-05 stops being relevant once CNI-11 points every node at the VIP.
   - `VMP-04` and `VMP-07`, `TALOS-01`, and `FLAT-06` wherever a playbook or
     template cites them.
   - `inventory.yaml` and `vars.yml.example` MUST describe one cluster whose
     nodes declare a distro, never two stacks running side by side.

   The supersession is not finished until
   `grep -rn "CNI-0[156]\|VMP-0[47]\|TALOS-01\|FLAT-06" infrastructure/ docs/`
   returns only historical text inside supersession markers.

Steps 1–5 are gated on open questions 1–4. They are cheap experiments — a scratch
VM and a throwaway cluster — and questions 1 and 2 can change this spec's shape,
so nothing else should be built until they are answered.

## Acceptance criteria

- [ ] `kubectl get nodes -o wide -L node-restriction.kubernetes.io/distro` shows
      one cluster, one endpoint, and at least two distinct OS images across the
      workers.
- [ ] `kubectl get nodes` returns the same six node names, with the same
      addresses, before and after a swap.
- [ ] A worker swap from Talos to Flatcar completes with **no workload outage**,
      Flux stays `Ready`, and the swapped node's authoritative distro label is
      correct.
- [ ] The reverse swap, Flatcar to Talos, also completes, and the runner pods
      pinned by 0017 FORGE-14 stay schedulable throughout — MIX-16 refuses the
      swap that would break them.
- [ ] A swap interrupted mid-drain, then re-run, converges without operator
      surgery.
- [ ] With one worker drained, every pod on the remaining two workers is
      `Running`. This is MIX-12's capacity claim, tested.
- [ ] `00-cluster-pki.yml` re-run changes nothing; deleting Talos's rendered
      `secrets.yaml` and re-running reproduces a byte-identical file.
- [ ] No worker holds a CA private key: grep the rendered worker artifacts for
      `ca.key` and `-----BEGIN` key blocks and find none (MIX-05).
- [ ] `remove-vms.yml` refuses to destroy a VM whose Node object exists, and
      `-e teardown=true` still empties the cluster.
- [ ] Kill the current VIP holder: `kubectl` through the generated kubeconfig
      keeps working. This is 0016 CNI-09's criterion, now against one cluster.
- [ ] A PVC bound on a swapped node re-attaches after the swap with no manual
      intervention.
- [ ] `control_plane_distro=flatcar` from a cold build produces the same cluster
      shape, endpoint and application state as `=talos`.

## Known limitations

- Swapping in place means N-1 workers for the duration, so single-replica RWO
  workloads — Forgejo (0017 FORGE-10) is the one that matters — are down for that
  window.
- The cluster CA private key is in the repository, encrypted. SOPS is the control,
  consistent with 0017's stated invariant, but repository compromise plus age-key
  compromise is total cluster compromise.
- Heterogeneous nodes mean pods can behave per-node. Deliberate, and 0010's new
  data source, but a genuinely new class of bug.
- A `control_plane_distro` change is a rebuild, so the *control-plane* half of the
  distro comparison stays serialized. This is the one axis on which the
  two-cluster model was better, and spec 0010's rewrite says so.
- Cilium's value set is constrained to the intersection of datapath features every
  node distro's kernel supports. A value one kernel cannot satisfy fails on *some*
  nodes, presenting as a partial DaemonSet outage rather than a failed install.
- Nothing yet enforces the Talos-to-Kubernetes version pairing, which MIX-22
  centralizes but does not validate. Already a 0013 limitation; the consequences
  are now cluster-wide.

## Open questions

Questions 1–4 MUST be answered experimentally before this spec moves from `Draft`
to `Accepted`. Questions 1 and 2 can change its shape.

1. **On the critical path for the default configuration.** Does `kubeadm join`
   work against a **Talos** control plane, given a synthesized `kubeadm-config`,
   `kubelet-config` and `cluster-info` plus bootstrapper RBAC — or is MIX-20's raw
   kubelet-bootstrap path required? With `control_plane_distro: talos` as the
   default, this is how the first mixed node gets in.
2. **Could change this spec's shape.** Does a Talos **worker** function fully —
   `talosctl logs`, `dmesg`, `upgrade`, `reset` — when no Talos control plane, and
   therefore no trustd, exists? A worker's `apid` obtains its server certificate
   from trustd, which runs on Talos control planes. The kubelet side should be
   fine, since it needs only the CA certificate, the token and the endpoint, so
   the failure mode is a node that *works* in Kubernetes and is *unmanageable* as
   a Talos node — the worst kind of half-success. Mitigations in order: keep
   `control_plane_distro: talos` (which makes open question 2 a *reason* for the
   default rather than a preference); or place the full `machine.ca` on workers,
   which is a real blast-radius increase and fights MIX-05; or accept degraded,
   re-provision-only management for Talos workers under a kubeadm control plane.
3. Does `talosctl gen secrets` at the pinned version import an external Kubernetes
   PKI, and which of the CAs and key pairs does it cover? There is a robust
   fallback: `secrets.yaml` is a plain YAML document whose schema 0013's
   templates index into (`certs.k8s.crt`, `certs.etcd.key`,
   `certs.k8saggregator`, `certs.k8sserviceaccount.key`, `secrets.bootstraptoken`,
   `trustdinfo.token`, `cluster.id`), so it can be Jinja-rendered from the bundle
   without talosctl's help. That turns a blocking unknown into a choice between
   two implementations — but the choice must be made deliberately.
4. Does `kubeadm init` reliably adopt a pre-seeded `/etc/kubernetes/pki`, and does
   the running cluster's CA fingerprint match the bundle's? kubeadm reuses
   existing files in `--cert-dir` rather than regenerating, which is what MIX-04
   relies on, but a partially seeded directory can produce a cluster with a CA you
   did not intend — which is why 0014 FLAT-02's amendment adds a verification
   step.
5. Do Talos and Flatcar kubelets agree closely enough on cgroup and seccomp
   defaults that identical pod specs behave identically? First test case is 0017's
   rootless DinD, which FORGE-14 already assumes they do not.
6. Does deleting and re-creating a Node with the same name leave `CSINode`,
   `Lease` or `VolumeAttachment` objects that delay or block PV re-attach? A
   lingering `VolumeAttachment` for a destroyed VM can block for the six-minute
   force-detach timeout or longer. Needs a dedicated test with a bound PVC.
7. Is the single VIP sufficient for Cilium on every node, or does the datapath's
   API dependence justify CNI-11's per-node API proxy upgrade path — on every
   distro, never on some?
8. Is a `control_plane_distro` change truly a rebuild — is etcd data written under
   Talos's secretbox provider unreadable to a kubeadm control plane? If it is, the
   "compare control planes by alternating" method in the rewritten 0010 always
   costs a full restore, and that should be stated as its price.
9. Does proxmox-csi-plugin's `topology.kubernetes.io/zone` handling survive a
   node's destruction and re-creation on the same Proxmox host? This is already
   0008's open question; MIX-28 makes it load-bearing.
10. With one worker drained, do all workloads from 0009 and 0017 actually schedule
    on the remaining two? If not, the swap procedure needs a maintenance window
    and MIX-12's envelope needs revising before this spec is accepted.
