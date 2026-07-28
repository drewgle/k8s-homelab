# 0016 — Cluster networking: Cilium

**Status:** Accepted
**Serves goals:** Learning (k8s, networking); distro evaluation; presentation
**Depends on:** [0013](0013-talos-cluster-lifecycle.md),
[0014](0014-flatcar-cluster-lifecycle.md) (both install the CNI)
**Affects:** [0009](0009-platform-services.md) (load balancing and ingress)

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

**Cilium**, on both node operating systems, with kube-proxy replacement
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
   Under Cilium both stacks become "cluster comes up with no CNI, then Helm
   installs Cilium" — identical, so 0010 measures the operating systems.

## Requirements

- **CNI-01** Both stacks MUST run the same CNI at the same version, from
  `versions.yaml`. A difference here invalidates spec 0010.
- **CNI-02** The Kubernetes bootstrap MUST NOT install any CNI of its own.
  Talos sets `cluster.network.cni.name: none`; Flatcar's kubeadm run installs
  no CNI addon. Nodes stay `NotReady` until Cilium is installed — that is
  expected, not a fault.
- **CNI-03** `kubernetes_cni` MUST only ever take values the consuming layer
  accepts. Talos's `cni.name` accepts `none`, `flannel` or `custom` only, so
  `cilium` MUST be translated to `none` in the template rather than passed
  through. (Passing it through was a live bug before this spec.)
- **CNI-04** kube-proxy replacement MUST be enabled
  (`kubeProxyReplacement=true`), and kube-proxy MUST NOT be installed:
  Talos sets `cluster.proxy.disabled: true`, Flatcar runs
  `kubeadm init --skip-phases=addon/kube-proxy`. Doing this at install time
  is a Helm value; doing it later is a migration on a live cluster.
- **CNI-05** Cilium MUST be able to reach the API server without a
  functioning Service network, since it is what provides that network. Talos
  uses [KubePrism](https://www.talos.dev/latest/kubernetes-guides/configuration/kubeprism/)
  (`k8sServiceHost: localhost`, `k8sServicePort: 7445`, already enabled in
  both machine config templates); Flatcar points at the control plane
  endpoint directly.
- **CNI-06** Talos requires explicit Helm values for its read-only rootfs and
  cgroup layout — `securityContext.capabilities.*`, `cgroup.autoMount.enabled=false`,
  `cgroup.hostRoot=/sys/fs/cgroup`, `ipam.mode=kubernetes` — per the
  [Talos Cilium guide](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium).
  These are Talos-specific and MUST NOT be copied to the Flatcar install.
- **CNI-07** Cilium MUST NOT take over load balancing or ingress. MetalLB and
  Envoy Gateway (spec 0009) stay as separate components — see below.
- **CNI-08** Installation happens in the Ansible layer, not GitOps. Argo CD
  cannot install the CNI because without a CNI no pods run, including Argo
  CD's. This is the one platform component that legitimately sits on the
  Ansible side of spec 0007's dividing line.
- **CNI-09** The cluster endpoint MUST be a floating VIP, never a node
  address. It is baked into the PKI, every `kubelet.conf`, the admin
  kubeconfig and Cilium's `k8sServiceHost`, so a node address means three
  control planes buy etcd quorum and nothing else — losing that one node
  takes the API from every client while two healthy API servers keep running.
  Each VIP MUST be free, on the VM VLAN, and outside the MetalLB pool.
  - Talos: `machine.network.interfaces[].vip.ip` on the control plane
    template — built in, etcd-elected, requires the control planes to share a
    layer 2 network (they do).
  - Flatcar: [kube-vip](https://kube-vip.io/) as a static pod on each control
    plane, ARP mode with leader election, pinned in `versions.yaml`. Service
    load balancing stays off — MetalLB owns that (spec 0009).
  - Both VIPs only exist after the control plane is up, so bootstrap MUST
    continue to use real node addresses and the playbooks MUST wait for the
    VIP before anything that goes through the kubeconfig.
  - `flatcar_vip_interface` MUST match the actual NIC name. A wrong value
    fails silently, so the playbook waits on the VIP and fails there instead.

### Why this is a spec 0010 finding, not just a fix

Talos ships control plane HA as one configuration stanza. kubeadm requires
choosing, installing and operating a separate component, and that component
collides with a kubeadm change: since Kubernetes 1.29 `admin.conf` is not
usable until `kubeadm init` completes, so kube-vip has to be pointed at
`super-admin.conf` for the duration of init and switched back after
([kube-vip#684](https://github.com/kube-vip/kube-vip/issues/684)). That
asymmetry — one line versus a component plus a bootstrap workaround — is
exactly the kind of day-2 difference spec 0010 exists to record, and it
should be journaled there rather than smoothed over.

A per-node local API proxy (the kubespray model, and effectively what
KubePrism does) would have made Flatcar mirror Talos more closely. It was
rejected for that reason: mimicking Talos here would erase the finding.

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
collapsing is a Helm value change on one cluster. Doing it on the Flatcar
cluster while Talos stays split is a clean experiment, and a good
presentation segment — the same workload served by three components and by
one.

## Implementation plan

1. `kubernetes_cni: "cilium"` becomes the default in `vars.yml.example`.
2. Talos: `cni.name: none` and `proxy.disabled: true` in both machine config
   templates; Cilium Helm install in `02-cluster-create.yml` after the
   kubeconfig lands.
3. Flatcar: `--skip-phases=addon/kube-proxy` on `kubeadm init`; Cilium Helm
   install with kube-proxy replacement in `02-cluster-bootstrap.yml`.
4. Enable Hubble with the UI, behind the Gateway once spec 0009 lands.
5. A baseline `default-deny` NetworkPolicy per application namespace, once
   there are applications — tracked in spec 0009, not here.

## Acceptance criteria

- [ ] Both clusters come up with all nodes `Ready` and no kube-proxy
      DaemonSet present.
- [ ] `cilium status` reports `KubeProxyReplacement: True` on both.
- [ ] A `NetworkPolicy` that denies traffic between two test pods is
      **actually enforced** — verified by a connection that fails, not by the
      object existing.
- [ ] Hubble shows live flows for both clusters.
- [ ] **Kill the first control plane on each cluster.** `kubectl` through the
      generated kubeconfig keeps working, existing pods keep networking, and
      new pods still schedule. This is the criterion CNI-09 exists for and it
      currently fails on both stacks.
- [ ] `versions.yaml` drives the Cilium version on both stacks; a Renovate
      bump changes one line per stack and nothing else.

## Known limitations

- Cilium is the hardest component here to debug when it misbehaves: the
  datapath is eBPF, not iptables rules you can read. `cilium-dbg` and Hubble
  are the tools, and learning them is part of the point.
- With kube-proxy gone, a Cilium failure takes Service routing with it.
  That is the accepted cost of CNI-04, and the reason CNI-07 keeps ingress
  out of the same blast radius.
- `helm` must be present on the control machine (Talos path) and on the
  first control plane node (Flatcar path). This is a prerequisite, not
  something the playbooks install.
- Both VIPs are layer 2: the control planes must sit on the same broadcast
  domain, which the single VM VLAN satisfies. Splitting the control planes
  across subnets later would require BGP instead.
- kube-vip failover depends on Kubernetes leader election, so its failure
  modes are coupled to the cluster's. keepalived + HAProxy would have kept
  the HA path independent of Kubernetes at the cost of two more components;
  that trade is revisitable if kube-vip proves fragile — and the outcome
  either way is journal material for spec 0010.
