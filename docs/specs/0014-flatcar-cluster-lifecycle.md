# 0014 — Flatcar Kubernetes cluster lifecycle

**Status:** Implemented
**Serves goals:** Learning (k8s, kubeadm); distro evaluation; repo organization
**Implementing files:** `infrastructure/ansible/playbooks/flatcar/02-cluster-bootstrap.yml`,
`update.yml`, `infrastructure/linux/flatcar/` (templates, versions)

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
- **FLAT-03** Initialization MUST be guarded on `/etc/kubernetes/admin.conf`,
  and each join guarded on that node's `/etc/kubernetes/kubelet.conf`, so a
  re-run over a live cluster is a no-op.
- **FLAT-04** Joins MUST use a token generated at join time
  (`kubeadm token create --ttl 1h --print-join-command`, plus a fresh
  certificate key for control planes). Bootstrap tokens are short-lived by
  design, so one captured at init time cannot be reused later.
- **FLAT-05** The CNI is installed after all nodes register, selected by
  `kubernetes_cni`: Cilium by Helm chart (the default, spec
  [0016](0016-cluster-networking-cilium.md)) or flannel by manifest, at the
  version in `versions.yaml`. No CNI is built in — until this step runs the
  nodes stay `NotReady`, which is expected, not a fault.
- **FLAT-09** When Cilium is the CNI, `kubeadm init` MUST run with
  `--skip-phases=addon/kube-proxy` (spec 0016, CNI-04). Removing kube-proxy
  after the fact is a live-cluster migration, so the choice is made at init
  time. Cilium is pointed at `flatcar_cluster_endpoint` for its API access,
  since no Service network exists while it is starting.
- **FLAT-06** The playbook MUST fetch `/etc/kubernetes/admin.conf` back to
  `infrastructure/linux/flatcar/generated/kubeconfig`. That file is the
  contract with spec [0007](0007-gitops-bootstrap.md), which selects between
  the two stacks by which kubeconfig exists.
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

## Interfaces

Consumes: `flatcar_cluster_name`, `flatcar_cluster_endpoint`,
`flatcar_pod_subnet`, `flatcar_service_subnet`, `flatcar_cluster_dns`,
`kubernetes_dns_domain`, `kubernetes_cni`, `flatcar_update_strategy`,
`flatcar_update_group`; inventory groups `flatcar_controlplane` and
`flatcar_worker` with `ansible_user: core`. Produces:
`infrastructure/linux/flatcar/generated/kubeconfig`.

## Acceptance criteria

- [ ] From provisioned VMs, `02-cluster-bootstrap.yml` completes and every
      node reaches `Ready` once the CNI is installed.
- [ ] Re-running the playbook against the live cluster changes nothing.
- [ ] `generated/kubeconfig` works from the control machine.
- [ ] `update.yml` moves the cluster to a newer Flatcar release with no
      workload outage, and no node reboots while it still holds pods.

## Known limitations

- There is no `health-check.yml` for Flatcar, while Talos has one. This is
  a repo asymmetry that skews the spec-0010 comparison and is tracked there
  as parity work.
- There is no `add-node.yml` for Flatcar either. Spec 0010 leaves it open
  whether to build one or record the asymmetry as a finding.
- Cluster state lives on the nodes (`/etc/kubernetes`, etcd on the control
  planes) rather than in a portable secrets bundle. Recovery therefore
  depends on etcd backups — spec [0015](0015-backup-and-recovery.md).
- The Cilium install shells out to `helm` on the first control plane,
  assuming Helm is present from Ignition; the playbook checks for it and
  fails clearly rather than installing it. The flannel path only needs
  `kubectl`.
- kube-vip's bootstrap workaround (super-admin.conf during `kubeadm init`)
  is a kubeadm-version-sensitive hack. If a future kubeadm changes the
  admin-kubeconfig handling again, this breaks at init time — loudly, at
  least, since the playbook waits on the VIP.
