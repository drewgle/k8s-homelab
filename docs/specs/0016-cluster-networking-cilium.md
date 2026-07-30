# 0016 — Cluster networking: Cilium

**Status:** Accepted
**Serves goals:** Learning (k8s, networking); distro evaluation; presentation
**Depends on:** [0013](0013-talos-cluster-lifecycle.md),
[0014](0014-flatcar-cluster-lifecycle.md) (both install the CNI)
**Affects:** [0009](0009-platform-services.md) (load balancing and ingress)
**Amended by:** [0019](0019-single-cluster-mixed-distro.md)
**Superseded requirements:** CNI-01 → CNI-10; CNI-05 → CNI-11; CNI-06 → CNI-12

## Context

The most consequential networking choice in the repo was being made by a
default in `vars.yml.example` — `kubernetes_cni: flannel` — with no rationale
recorded anywhere. This spec makes the choice explicitly and says what was
rejected.

The problem with flannel here is not that it lacks NetworkPolicy. It is that
it lacks it *silently*: NetworkPolicy is a core Kubernetes API, so the API
server accepts policy objects, `kubectl get networkpolicy` lists them, and
nothing enforces them. The architecture doc claimed micro-segmentation as a
defense-in-depth layer while the cluster had no policy enforcement at all —
a security control that appears present and is not.

## Decision

**Cilium**, on every node OS in the cluster, with kube-proxy replacement
enabled, and **without** absorbing load balancing or ingress.

### Options considered

| Option | NetworkPolicy | Notes |
|--------|---------------|-------|
| [Cilium](https://cilium.io/) (chosen) | yes, plus L7 | eBPF datapath; can also replace kube-proxy, MetalLB and the Gateway controller |
| [Calico](https://www.tigera.io/project-calico/) | yes | Simpler than Cilium, stays out of load balancing and ingress. The safe middle option |
| [flannel](https://github.com/flannel-io/flannel) (previous default) | **no** | Maintained and minimal; does pod networking and nothing else |

Cilium wins on four counts specific to this repo:

1. It makes the NetworkPolicy claim real.
2. Learning goal: an eBPF datapath is what production clusters actually run;
   flannel teaches a VXLAN tunnel.
3. Presentation goal:
   [Hubble](https://docs.cilium.io/en/stable/overview/intro/#what-is-hubble)'s
   live service map is the strongest visual in the stack and runs entirely
   locally, so it does not depend on venue networking.
4. **It removes an asymmetry that was skewing spec
   [0010](0010-node-os-evaluation.md).** Talos was using its built-in
   flannel; Flatcar applied a flannel manifest after bootstrap. Two different
   mechanisms meant the comparison was partly measuring this repo's plumbing.
   Under Cilium every distro becomes "the node comes up with no CNI, then the
   agent lands on it" — identical, so 0010 measures the operating systems. Spec
   [0019](0019-single-cluster-mixed-distro.md) took this further than intended:
   with one cluster there is one Cilium release, so sameness is structural rather
   than a rule anyone has to keep.

## Requirements

- **CNI-01** **Superseded by CNI-10 below.** *Historical text: Both stacks
  MUST run the same CNI at the same version, from `versions.yaml`. A difference
  here invalidates spec 0010.*
- **CNI-02** The Kubernetes bootstrap MUST NOT install any CNI of its own.
  Talos sets `cluster.network.cni.name: none`; Flatcar's kubeadm run installs
  no CNI addon. Nodes stay `NotReady` until Cilium is installed — that is
  expected, not a fault, and it applies to a node joining an existing cluster as
  much as to a fresh bootstrap (0019 MIX-17).
- **CNI-03** `kubernetes_cni` MUST only ever take values the consuming layer
  accepts. Talos's `cni.name` accepts `none`, `flannel` or `custom` only, so
  `cilium` MUST be translated to `none` in the template rather than passed
  through. (Passing it through was a live bug before this spec.)
- **CNI-04** kube-proxy replacement MUST be enabled
  (`kubeProxyReplacement=true`), and kube-proxy MUST NOT exist in the cluster.
  The mechanism follows `control_plane_distro` (0019 MIX-14): Talos sets
  `cluster.proxy.disabled: true`, kubeadm runs
  `init --skip-phases=addon/kube-proxy`. Doing this at install time is a Helm
  value; doing it later is a migration on a live cluster. Worker joins introduce
  no kube-proxy on either path, since it was only ever an addon DaemonSet.
- **CNI-05** **Superseded by CNI-11 below.** *Historical text: Cilium MUST be
  able to reach the API server without a functioning Service network, since it is
  what provides that network. Talos uses KubePrism (`k8sServiceHost: localhost`,
  `k8sServicePort: 7445`, already enabled in both machine config templates);
  Flatcar points at the control plane endpoint directly.*
- **CNI-06** **Superseded by CNI-12 below.** *Historical text: Talos requires
  explicit Helm values for its read-only rootfs and cgroup layout —
  `securityContext.capabilities.*`, `cgroup.autoMount.enabled=false`,
  `cgroup.hostRoot=/sys/fs/cgroup`, `ipam.mode=kubernetes` — per the Talos Cilium
  guide. These are Talos-specific and MUST NOT be copied to the Flatcar install.*
- **CNI-07** Cilium MUST NOT take over load balancing or ingress. MetalLB and
  Envoy Gateway (spec 0009) stay as separate components — see below.
- **CNI-08** Installation happens in the Ansible layer, not GitOps. Flux
  cannot install the CNI because without a CNI no pods run, including Flux's
  own controllers. This is the one platform component that legitimately sits
  on the Ansible side of spec 0007's dividing line.
- **CNI-09** The cluster endpoint MUST be a floating VIP, never a node
  address. It is baked into the PKI, every `kubelet.conf`, the admin
  kubeconfig and Cilium's `k8sServiceHost`, so a node address means three
  control planes buy etcd quorum and nothing else — losing that one node
  takes the API from every client while two healthy API servers keep running.
  The VIP MUST be free, on the VM VLAN, and outside the MetalLB pool: it is
  `cluster_vip` at `192.168.100.200` (0019 MIX-09, MIX-21).

  There is **one** VIP, and its mechanism follows `control_plane_distro`:
  - Talos: `machine.network.interfaces[].vip.ip` on the control plane
    template — built in, etcd-elected, requires the control planes to share a
    layer 2 network (they do).
  - kubeadm: [kube-vip](https://kube-vip.io/) as a static pod on each control
    plane, ARP mode with leader election, pinned in `versions.yaml`. Service
    load balancing stays off — MetalLB owns that (spec 0009).
    `flatcar_vip_interface` MUST match the actual NIC name; a wrong value fails
    silently, so the playbook waits on the VIP and fails there instead.
  - **Exactly one mechanism MUST be active.** Two ARP claimants for one address
    is a flapping VIP, which presents as intermittent API failure and is
    miserable to diagnose.
  - The VIP only exists after the control plane is up, so bootstrap MUST
    continue to use real node addresses and the playbooks MUST wait for the
    VIP before anything that goes through the kubeconfig.
- **CNI-10** Supersedes CNI-01. There is exactly **one** Cilium release for the
  cluster, at the version in `infrastructure/linux/cluster/versions.yaml` — one
  key, not one per distro. Version sameness across node distros is now structural
  rather than a rule, which is strictly stronger than CNI-01 was.
- **CNI-11** Supersedes CNI-05. Cilium MUST be able to reach the API server
  without a functioning Service network, since it is what provides that network,
  via **`k8sServiceHost` set to `cluster_vip`** and `k8sServicePort` 6443, on
  every node. A per-node API endpoint is not expressible from a single Helm
  release, so
  [KubePrism](https://www.talos.dev/latest/kubernetes-guides/configuration/kubeprism/)
  MUST NOT appear in Helm values — it stays enabled in Talos machine configs for
  Talos's own use. This adds no new dependency: CNI-09 already made the VIP the
  endpoint in the PKI, every kubeconfig and every kubelet config, so if the VIP is
  down the kubelets are already in trouble and Cilium is not the marginal risk.
  If VIP dependence proves fragile, the upgrade path is a per-node API proxy on
  *every* node distro, never on some.
- **CNI-12** Supersedes CNI-06. Every Helm value MUST be valid on every node
  distro in the cluster simultaneously. `cgroup.autoMount.enabled=false`,
  `cgroup.hostRoot=/sys/fs/cgroup`, `ipam.mode=kubernetes` and the explicit
  `securityContext.capabilities.*` lists are therefore **cluster-wide
  requirements, not Talos accommodations**: they are correct on any systemd host
  with cgroup v2 already mounted, and they keep the agent unprivileged everywhere.
  Values MUST be restricted to the intersection of datapath features all node
  distros' kernels support — a value one kernel cannot satisfy fails on *some*
  nodes only, which presents as a partial DaemonSet outage rather than a failed
  install.

### Why the VIP mechanism is a spec 0010 finding, not just a fix

Talos ships control plane HA as one configuration stanza. kubeadm requires
choosing, installing and operating a separate component, and that component
collides with a kubeadm change: since Kubernetes 1.29 `admin.conf` is not
usable until `kubeadm init` completes, so kube-vip has to be pointed at
`super-admin.conf` for the duration of init and switched back after
([kube-vip#684](https://github.com/kube-vip/kube-vip/issues/684)). That
asymmetry — one line versus a component plus a bootstrap workaround — is
exactly the kind of day-2 difference spec 0010 exists to record, and it
should be journaled there rather than smoothed over.

Under spec 0019 this is specifically a **control-plane-distro** finding: it is
only observable while that distro holds the control plane, so it belongs in
0010's serial half rather than its concurrent one.

A per-node local API proxy (the kubespray model, and effectively what
KubePrism does) would have made kubeadm mirror Talos more closely. It was
rejected for that reason: mimicking Talos here would erase the finding. CNI-11
keeps it as the documented upgrade path if the single VIP proves fragile — but
then on every node distro, because a proxy on some nodes and not others
reintroduces exactly the per-node divergence CNI-12 forbids.

## Why Cilium does not absorb MetalLB and Envoy Gateway

Both [Cilium L2 announcements](https://docs.cilium.io/en/stable/network/l2-announcements/)
and [Cilium Gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
require `kubeProxyReplacement=true`, which CNI-04 satisfies — so the option
stays open. It is deliberately not taken, for three reasons:

- **Blast radius.** With the components separate, a bad Envoy Gateway upgrade
  breaks ingress and the cluster is still reachable to fix it. Collapsed, one
  bad Cilium upgrade takes pod networking, Service IPs and ingress at the
  same moment. There is one operator here.
- **Client source IPs.** Cilium L2 announcements are incompatible with
  `externalTrafficPolicy: Local`, so adopting them means giving up real
  client addresses at the ingress — which is exactly the data the monitoring
  stack in spec 0009 wants.
- **Portability.** Spec 0009 chose Gateway API so that swapping the ingress
  implementation is a `GatewayClass` change rather than an application
  manifest migration. Making the CNI the Gateway implementation gives that
  property back.

This is a decision to revisit, not a closed door: with CNI-04 in place,
collapsing is a Helm value change. It is a weaker experiment than it was,
though, and spec 0019 is why — the original plan was to collapse the Flatcar
cluster while Talos stayed split, giving a side-by-side comparison. With one
cluster it is a whole-cluster change with no control group, so it has to be run
as a before-and-after on the same cluster instead. Still a good presentation
segment — the same workload served by three components and by one — just no
longer a controlled one.

## Implementation plan

1. `kubernetes_cni: "cilium"` becomes the default in `vars.yml.example`.
2. Talos: `cni.name: none` and `proxy.disabled: true` in both machine config
   templates.
3. kubeadm: `--skip-phases=addon/kube-proxy` on `kubeadm init`.
4. One Cilium Helm install in a distro-neutral play, with `k8sServiceHost` set to
   `cluster_vip` (CNI-11) and the CNI-12 value set. This moves out of
   `02-cluster-create.yml` and `02-cluster-bootstrap.yml`, which each installed
   their own copy.
5. Enable Hubble with the UI, behind the Gateway once spec 0009 lands.
6. A baseline `default-deny` NetworkPolicy per application namespace, once
   there are applications — tracked in spec 0009, not here.

## Acceptance criteria

- [ ] The cluster comes up with all nodes `Ready` and no kube-proxy DaemonSet
      present.
- [ ] `cilium status` reports `KubeProxyReplacement: True`, and the cilium-agent
      is `Ready` on **every** node, reporting the same datapath mode regardless
      of node distro (CNI-12).
- [ ] A `NetworkPolicy` that denies traffic between two test pods is
      **actually enforced** — verified by a connection that fails, not by the
      object existing.
- [ ] Hubble shows live flows, including pod-to-pod traffic that crosses a
      distro boundary.
- [ ] **Kill the first control plane.** `kubectl` through the generated
      kubeconfig keeps working, existing pods keep networking, and new pods still
      schedule. This is the criterion CNI-09 exists for.
- [ ] `infrastructure/linux/cluster/versions.yaml` drives the Cilium version; a
      Renovate bump changes one line and nothing else (CNI-10).
- [ ] A node swapped to a different distro (0019 MIX-23) has its cilium-agent
      `Ready` before it is uncordoned.

## Known limitations

- Cilium is the hardest component here to debug when it misbehaves: the
  datapath is eBPF, not iptables rules you can read. `cilium-dbg` and Hubble
  are the tools, and learning them is part of the point.
- With kube-proxy gone, a Cilium failure takes Service routing with it.
  That is the accepted cost of CNI-04, and the reason CNI-07 keeps ingress
  out of the same blast radius.
- `helm` must be present wherever the install runs — the control machine, or the
  first control plane node. This is a prerequisite, not something the playbooks
  install.
- The VIP is layer 2: the control planes must sit on the same broadcast
  domain, which the single VM VLAN satisfies. Splitting the control planes
  across subnets later would require BGP instead.
- CNI-12 caps the value set at the intersection of what every node distro's
  kernel supports. A feature available on one distro and not another is
  unavailable to the cluster, and the failure mode if it is enabled anyway is a
  partial DaemonSet outage rather than a clean install failure.
- kube-vip failover depends on Kubernetes leader election, so its failure
  modes are coupled to the cluster's. keepalived + HAProxy would have kept
  the HA path independent of Kubernetes at the cost of two more components;
  that trade is revisitable if kube-vip proves fragile — and the outcome
  either way is journal material for spec 0010.
