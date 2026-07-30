# 0014 — Flatcar Kubernetes cluster lifecycle

**Status:** Accepted
**Serves goals:** Learning (k8s, kubeadm); distro evaluation; repo organization
**Planned files:** `infrastructure/ansible/playbooks/flatcar/02-cluster-bootstrap.yml`,
`update.yml`, `infrastructure/linux/flatcar/` (templates, versions)
**Amended by:** [0019](0019-single-cluster-mixed-distro.md)
**Superseded requirements:** FLAT-06 → FLAT-10

## Context

The Flatcar counterpart to spec [0013](0013-talos-cluster-lifecycle.md), and
the reason the node-OS evaluation (spec
[0010](0010-node-os-evaluation.md)) has anything to compare. Where Talos is
driven entirely through a machine API, Flatcar is a conventional Linux host:
Ignition lays down binaries and a kubeadm config at first boot, then Ansible
connects over SSH as the `core` user and runs
[kubeadm](https://kubernetes.io/docs/reference/setup-tools/kubeadm/). That
difference — API versus SSH, declarative config versus imperative steps — is
itself the evaluation data point.

Since spec [0019](0019-single-cluster-mixed-distro.md) this spec covers two
separable things, and the split matters: the **kubeadm control-plane path**, which
runs only when `control_plane_distro == flatcar`, and the **worker path**, which
runs whenever any node declares `node_distro: flatcar` regardless of what holds
the control plane. Because kubeadm is the generic path, the worker half is also
the template every future distro follows.

## Requirements

- **FLAT-01** Nodes arrive with `/opt/bin/kubeadm` and
  `/etc/kubernetes/kubeadm-config.yaml` already in place from Ignition. The
  bootstrap playbook MUST verify this and fail with a clear message rather
  than attempting to install Kubernetes itself — a missing binary means the
  Ignition config did not apply, which is a provisioning bug, not a
  bootstrap one.
- **FLAT-02** `kubeadm init` runs on the *first* control plane only, with
  `--upload-certs` so the remaining control planes can join with a
  certificate key rather than manual copying. `controlPlaneEndpoint` is the
  VIP in `host:port` form (kubeadm rejects a URL with a scheme) and the
  certSANs cover the VIP plus every control plane address, so any of them can
  serve the API under the shared name.

  `/etc/kubernetes/pki` MUST be **pre-seeded from the cluster PKI bundle** (0019
  MIX-02, MIX-04) before init, so kubeadm adopts the existing CAs rather than
  generating its own — that is what makes the cluster's identity survive a change
  of control-plane distro. Immediately after init the playbook MUST **verify the
  running cluster's CA fingerprint matches the bundle's**: kubeadm reuses whatever
  it finds in `--cert-dir`, so a partially seeded directory yields a cluster with
  a CA nobody intended, and the failure is otherwise silent.
- **FLAT-03** Initialization MUST be guarded on `/etc/kubernetes/admin.conf`,
  and each join guarded on that node's `/etc/kubernetes/kubelet.conf`, so a
  re-run over a live cluster is a no-op.
- **FLAT-04** The bootstrap token's *value* comes from the cluster PKI bundle, and
  each provisioning or join run MUST ensure the matching `bootstrap-token-<id>`
  Secret exists with a bounded TTL covering the join window, without extending it
  afterwards (0019 MIX-06). Server-side validity stays short-lived by design, so
  a token left valid after a join is a defect. Control-plane certificate keys
  remain ephemeral, generated per join.
- **FLAT-05** The nodes carry no built-in CNI — until the Cilium agent lands on
  them they stay `NotReady`, which is expected, not a fault. Installing Cilium is
  **not** this playbook's job: there is one release for the cluster
  (spec [0016](0016-cluster-networking-cilium.md), CNI-10), installed by a
  distro-neutral play.
- **FLAT-06** **Superseded by FLAT-10.** *Historical text: The
  playbook MUST fetch `/etc/kubernetes/admin.conf` back to
  `infrastructure/linux/flatcar/generated/kubeconfig`. That file is the contract
  with spec 0007, which selects between the two stacks by which kubeconfig
  exists.*
- **FLAT-07** `update.yml` performs OS updates one node at a time
  (`serial: 1`): cordon, drain with a bounded timeout, let
  [update_engine](https://www.flatcar.org/docs/latest/setup/releases/update-strategies/)
  reboot the node, wait for `Ready`, uncordon. A node MUST NOT be rebooted
  while it still holds pods.
- **FLAT-08** OS version is *not* pinned at run time: nodes track the
  configured release channel through update_engine. `versions.yaml` pins only
  the image used to provision new nodes. This is the opposite of Talos's
  model (TALOS-03) and is deliberate — it is one of the things spec 0010
  measures.
- **FLAT-09** `kubeadm init` MUST run with `--skip-phases=addon/kube-proxy`
  (spec 0016, CNI-04). Removing kube-proxy after the fact is a live-cluster
  migration, so the choice is made at init time. Cilium's API access is the
  cluster VIP (0016 CNI-11), not a Flatcar-specific endpoint.
- **FLAT-10** Supersedes FLAT-06. When Flatcar holds the control plane, the
  playbook MUST fetch `/etc/kubernetes/admin.conf` back to the single
  distro-neutral path `infrastructure/linux/cluster/generated/kubeconfig` — the
  contract with spec [0007](0007-gitops-bootstrap.md). There is one cluster and one
  kubeconfig (0019 MIX-01), so there is nothing to select between and no
  `vm_type` autodetection.
- **FLAT-11** kube-vip MUST be deployed only when `control_plane_distro ==
  flatcar`. There is exactly one VIP with exactly one claimant (0019 MIX-21, 0016
  CNI-09); running kube-vip on a cluster whose control plane is Talos means two
  mechanisms claiming `192.168.100.200`.
- **FLAT-12** A Flatcar node MUST be able to join as a **worker** under any
  `control_plane_distro`, satisfying 0019 MIX-17 with no CA private key on the
  node (MIX-05). Under a Talos control plane, kubeadm's discovery and config-fetch
  phases look for artifacts Talos does not create, so the join uses whichever of
  0019 MIX-20's two paths that spec settles on. Because kubeadm is the generic
  path, this requirement is also the template for every future distro.

## Interfaces

Consumes: `cluster_name`, `cluster_endpoint`, `cluster_vip`,
`cluster_pod_subnet`, `cluster_service_subnet`, `cluster_dns`,
`kubernetes_dns_domain`, `kubernetes_cni`, `control_plane_distro`,
`flatcar_update_strategy`, `flatcar_update_group`, `flatcar_vip_interface`;
inventory groups `kubernetes_controlplane` and `kubernetes_worker` filtered to
hosts with `node_distro: flatcar`, connecting as `core` (0019 MIX-13). Produces,
when Flatcar holds the control plane:
`infrastructure/linux/cluster/generated/kubeconfig`.

## Acceptance criteria

- [ ] From provisioned VMs with `control_plane_distro: flatcar`,
      `02-cluster-bootstrap.yml` completes and every node reaches `Ready` once
      Cilium is installed.
- [ ] Re-running the playbook against the live cluster changes nothing.
- [ ] `infrastructure/linux/cluster/generated/kubeconfig` works from the control
      machine (FLAT-10).
- [ ] The CA fingerprint in the running cluster matches the PKI bundle's
      (FLAT-02).
- [ ] A Flatcar worker joins a cluster whose control plane is **Talos**, reaches
      `Ready`, and holds no CA private key (FLAT-12).
- [ ] kube-vip is absent when `control_plane_distro: talos` (FLAT-11).
- [ ] `update.yml` moves the Flatcar nodes to a newer release with no
      workload outage, and no node reboots while it still holds pods.

## Known limitations

- The Cilium install assumes `helm` is present from Ignition where it runs; the
  playbook checks for it and fails clearly rather than installing it.
- kubeadm expects cluster-side artifacts only kubeadm creates
  (`kube-public/cluster-info`, `kube-system/kubeadm-config`,
  `kube-system/kubelet-config`). Under a Talos control plane those must either be
  synthesized or bypassed (FLAT-12, 0019 MIX-20), and the two options fail in
  completely different ways — which is why 0019 requires recording which is in
  use.

### Resolved by spec 0019

Three limitations an earlier draft of this spec carried are gone, and by
deletion rather than by building anything:

- *No `health-check.yml` for Flatcar, while Talos has one*, and *no
  `add-node.yml` either*. Both were asymmetries in the planned automation, not in
  the operating systems. With one cluster there is one distro-neutral health check
  and one node-add play (0019 MIX-18), so the asymmetry cannot exist. Spec 0010 no
  longer carries them as parity work.
- *Cluster state lives on the nodes rather than in a portable secrets bundle.*
  It lives instead in the cluster PKI bundle (0019 MIX-02), committed encrypted,
  the same for every distro. Recovery still wants etcd backups for cluster *data*
  (spec [0015](0015-backup-and-recovery.md)), but cluster *identity* is portable —
  which was the actual gap.
- kube-vip's bootstrap workaround (super-admin.conf during `kubeadm init`)
  is a kubeadm-version-sensitive hack. If a future kubeadm changes the
  admin-kubeconfig handling again, this breaks at init time — loudly, at
  least, since the playbook waits on the VIP.
