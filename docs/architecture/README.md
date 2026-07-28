# Architecture Overview

This document provides a comprehensive overview of the homelab infrastructure architecture, including component relationships, data flows, and design decisions.

> **How to read this document.** It describes the *target* end state. Where a
> layer is already built, the [specs](../specs/) are authoritative and this
> page summarizes them; where it is not, the spec is the plan and this page is
> a sketch. Any conflict between the two is a bug in this page. Sections
> below name the spec that owns each area.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          HomeLab Infrastructure                         │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                 │
│  │   Physical  │    │   Physical  │    │   Physical  │                 │
│  │   Server 1  │    │   Server 2  │    │   Server 3  │                 │
│  │             │    │             │    │             │                 │
│  │ ┌─────────┐ │    │ ┌─────────┐ │    │ ┌─────────┐ │                 │
│  │ │Proxmox  │ │    │ │Proxmox  │ │    │ │Proxmox  │ │                 │
│  │ │   VE    │ │    │ │   VE    │ │    │ │   VE    │ │                 │
│  │ └─────────┘ │    │ └─────────┘ │    │ └─────────┘ │                 │
│  └─────────────┘    └─────────────┘    └─────────────┘                 │
│         │                   │                   │                      │
│         └───────────────────┼───────────────────┘                      │
│                             │                                          │
│         ┌──────────────────┐│┌──────────────────┐                       │
│         │      Ceph        │││   Proxmox VE     │                       │
│         │  Storage Pool    │││   Clustering     │                       │
│         └──────────────────┘│└──────────────────┘                       │
│                             │                                          │
│         ┌───────────────────▼───────────────────┐                       │
│         │              Virtual Machines         │                       │
│         │                                       │                       │
│         │  ┌─────────────┐  ┌─────────────┐     │                       │
│         │  │   Talos     │  │   Talos     │     │                       │
│         │  │Control Plane│  │  Workers    │     │                       │
│         │  └─────────────┘  └─────────────┘     │                       │
│         └───────────────────────────────────────┘                       │
│                             │                                          │
│         ┌───────────────────▼───────────────────┐                       │
│         │          Kubernetes Cluster           │                       │
│         │                                       │                       │
│         │  ┌─────────┐ ┌─────────┐ ┌─────────┐  │                       │
│         │  │ Master  │ │ Master  │ │ Master  │  │                       │
│         │  │  Node   │ │  Node   │ │  Node   │  │                       │
│         │  └─────────┘ └─────────┘ └─────────┘  │                       │
│         │                                       │                       │
│         │  ┌─────────┐ ┌─────────┐ ┌─────────┐  │                       │
│         │  │ Worker  │ │ Worker  │ │ Worker  │  │                       │
│         │  │  Node   │ │  Node   │ │  Node   │  │                       │
│         │  └─────────┘ └─────────┘ └─────────┘  │                       │
│         └───────────────────────────────────────┘                       │
│                             │                                          │
│         ┌───────────────────▼───────────────────┐                       │
│         │            Applications                │                       │
│         │                                       │                       │
│         │ 🐳 Containers  📊 Monitoring          │                       │
│         │ 🔄 GitOps     🔒 Security            │                       │
│         │ 🌐 Web Apps   💾 Storage              │                       │
│         └───────────────────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────────────┘
```

## Component Architecture

### Infrastructure Layer

#### Physical Hardware
- **3+ Physical Servers**: Standard x86_64 hardware
- **Network**: Gigabit+ networking between hosts
- **Storage**: Local SSDs/NVMe for OS, NVMe for Ceph storage

#### Proxmox VE Hypervisor
- **Purpose**: Type-1 hypervisor for VM management
- **Features**:
  - High availability cluster
  - Live migration of VMs
  - Web-based management interface
  - Built-in backup and restore

#### Ceph Distributed Storage
- **Purpose**: Unified storage backend for VMs and containers
- **Features**:
  - Fault tolerant (`size 3` / `min_size 2` — survives one node loss and
    stays writable)
  - Self-healing and self-managing
  - Block, object, and file storage
  - Horizontal scaling

### Container Orchestration Layer

#### Talos Linux
- **Purpose**: Immutable Linux distribution for Kubernetes
- **Features**:
  - API-driven configuration
  - Minimal attack surface
  - Automatic security updates
  - Declarative node management

#### Kubernetes Cluster
- **Control Plane**: 3 nodes for HA
- **Worker Nodes**: N nodes for workload distribution
- **Networking**: Cilium, with kube-proxy replacement — see
  [spec 0016](../specs/0016-cluster-networking-cilium.md). Same CNI and
  version on both node OSes, so the OS comparison measures the OS. flannel
  remains selectable via `kubernetes_cni` but is not the default: it does not
  implement NetworkPolicy, and it fails to do so *silently*.
- **Storage**: a CSI driver against the *existing* Proxmox Ceph cluster —
  see [spec 0008](../specs/0008-kubernetes-storage.md). Longhorn was
  considered and rejected: it would build a second replicated storage layer
  on top of VM disks that are already Ceph-backed, and it sidesteps the goal
  of learning Ceph.
- Lifecycle: [spec 0013](../specs/0013-talos-cluster-lifecycle.md) (Talos),
  [spec 0014](../specs/0014-flatcar-cluster-lifecycle.md) (Flatcar).

### Application Layer

#### GitOps Management
- **Flux**: Continuous reconciliation of everything above the cluster, managed
  by the Flux Operator so Flux's own version is a declarative field
  ([spec 0007](../specs/0007-gitops-bootstrap.md))
- **Git Repository**: Single source of truth for configuration

#### Core Services

Specified in [spec 0009](../specs/0009-platform-services.md); none of it is
built yet.

- **Load balancing**: MetalLB in L2 mode on the VM VLAN
- **Ingress**: Gateway API, implemented by Envoy Gateway, with cert-manager
  issuing Let's Encrypt certificates over DNS-01. *Not* ingress-nginx — that
  project was retired by Kubernetes SIG Network in March 2026 and receives no
  further fixes, including security fixes.
- **Monitoring**: Prometheus + Grafana stack
- **Logging**: Loki, with Grafana Alloy as the collector (Promtail reached
  end of life in March 2026)
- **Public exposure**: Cloudflare Tunnel, outbound-only
  ([spec 0012](../specs/0012-public-exposure-cloudflare.md))

## Design Decisions

### Infrastructure as Code
**Decision**: Use Ansible for infrastructure automation
**Rationale**: 
- Declarative configuration management
- Agentless operation
- Strong community support
- Excellent integration with existing tools

### Immutable Infrastructure
**Decision**: Use Talos Linux for Kubernetes nodes
**Rationale**:
- Reduced attack surface
- Simplified maintenance
- Consistent environments
- API-driven management

Flatcar Container Linux with kubeadm is maintained as an alternative node OS
(`infrastructure/ansible/playbooks/flatcar/`) for comparison. The two stacks
share the VM VLAN but have disjoint node IPs, pod CIDRs, service CIDRs and
cluster names, so both can run at once — capacity permitting. The comparison
itself is [spec 0010](../specs/0010-node-os-evaluation.md).

### Storage Strategy
**Decision**: Ceph for distributed storage
**Rationale**:
- High availability without vendor lock-in
- Unified storage for VMs and containers
- Self-healing and automatic rebalancing
- Proven at scale

### Container Orchestration
**Decision**: Kubernetes for container management
**Rationale**:
- Industry standard
- Rich ecosystem
- Declarative configuration
- Strong automation capabilities

### GitOps Approach
**Decision**: Flux for application deployment
**Rationale**:
- Git as single source of truth
- Automated drift detection
- Audit trail for all changes
- Simplified rollback procedures
- Native SOPS decryption, so encrypted secrets are ordinary committed files
  rather than a repo-server plugin
- A quarter of Argo CD's memory footprint, which matters on homelab VMs

Argo CD was the earlier choice and would also have worked; the trade — and the
one thing lost, its UI — is recorded in
[spec 0007](../specs/0007-gitops-bootstrap.md).

## Network Architecture

```
Internet
    │
    ▼
┌───────────────┐
│   Firewall    │
│   / Router    │
└───────┬───────┘
        │
        ▼
┌───────────────┐
│   Core        │
│   Switch      │
└───┬───┬───┬───┘
    │   │   │
    ▼   ▼   ▼
┌───────┐ ┌───────┐ ┌───────┐
│Server1│ │Server2│ │Server3│
│  PVE  │ │  PVE  │ │  PVE  │
└───────┘ └───────┘ └───────┘
```

### Network Zones

Defaults from `infrastructure/ansible/vars.yml.example`:

- **Management Network**: 192.168.1.0/24 (Proxmox hosts, Ceph public network)
- **VM Network**: 192.168.100.0/24 on VLAN 100 (Kubernetes nodes)
- **Storage Network**: 10.0.1.0/24 (optional dedicated Ceph cluster network)

The two Kubernetes stacks are addressed disjointly so both can run at once
(spec [0006](../specs/0006-vm-platform.md), VMP-07):

| | Talos | Flatcar |
|---|---|---|
| Node IPs | 192.168.100.201-213 | 192.168.100.221-233 |
| Pod CIDR | 10.244.0.0/16 | 10.245.0.0/16 |
| Service CIDR | 10.96.0.0/12 | 10.112.0.0/12 |

## Security Architecture

### Defense in Depth
1. **Physical Security**: Locked server room/rack
2. **Host Hardening**: SSH lockdown, sysctl hardening, auditd, fail2ban —
   [spec 0005](../specs/0005-node-hardening.md) *(built)*
3. **Network Segmentation**: VLAN 100 for VMs; the built-in Proxmox firewall
   (nftables) on the hosts, default-drop inbound *(built)*
4. **VM Isolation**: Proxmox VM boundaries *(built)*
5. **Container Security**: Pod security standards *(not started)*
6. **Application Security**: Security policies and scanning *(not started)*

### Access Control
- **SSH Keys**: No password authentication *(built)*
- **RBAC**: Fine-grained Kubernetes permissions *(default RBAC only)*
- **Network Policies**: micro-segmentation in K8s — enforceable now that
  Cilium is the CNI ([spec 0016](../specs/0016-cluster-networking-cilium.md));
  baseline policies are written once there are applications to scope them to
  *(enforcement available, policies not yet written)*
- **Service Mesh**: not planned. It would be the largest single piece of
  complexity in the stack for no need this homelab has.

### Secrets Management
- **Ansible Vault**: encrypted variables for infrastructure
- **SOPS + age**: Kubernetes secrets committed encrypted and decrypted by Flux
  at reconcile time ([spec 0007](../specs/0007-gitops-bootstrap.md)). The age
  private key lives in the Ansible Vault-encrypted variables file, which makes
  the vault password the single out-of-band secret for the whole system —
  covered by [spec 0015](../specs/0015-backup-and-recovery.md)
- Generated cluster secrets, machine configs and kubeconfigs live in
  gitignored `generated/` directories and are never committed

## Monitoring and Observability

### Metrics
- **Infrastructure**: Node Exporter, Proxmox Exporter
- **Kubernetes**: kube-state-metrics, cadvisor
- **Applications**: Custom metrics via Prometheus

### Logging
- **Centralized**: Loki, collected by Grafana Alloy
- **Application Logs**: Structured logging with JSON
- **Audit Logs**: Kubernetes API server logs

### Alerting
- **AlertManager**: ships with kube-prometheus-stack; routing stays default
  until there is an audience for alerts
- **Grafana**: visual dashboards and alert rules

## Backup and Disaster Recovery

Specified in [spec 0015](../specs/0015-backup-and-recovery.md). **None of it
is implemented yet** — treat this section as the plan, not a guarantee.

### Data Protection
- **Cluster identity**: Talos secrets bundle, kubeadm PKI, and the SOPS age
  key — small, static, and the difference between "rebuild" and "gone"
- **VM Backups**: `vzdump` to Proxmox Backup Server or a NAS
- **K8s Backups**: Velero for application data and CSI volume snapshots
- **Configuration Backups**: this git repository
- **Storage Replication**: Ceph replication pools — note that replication is
  *not* a backup; it protects against a node loss, not against deletion

### Recovery objectives

Per-scenario targets live in spec 0015. They are estimates until the drill in
that spec measures them; this page will not restate numbers that have never
been tested.

## Scalability Considerations

### Horizontal Scaling
- **Compute**: Add Proxmox nodes to cluster
- **Storage**: Add OSDs to Ceph cluster
- **K8s Workers**: Add nodes to Kubernetes cluster
- **Applications**: Scale deployments via HPA

### Vertical Scaling
- **VM Resources**: Hot-plug CPU/memory in Proxmox
- **Storage Expansion**: Expand PVCs in Kubernetes
- **Ceph OSDs**: Add disks to existing nodes

## Performance Optimization

### Storage Performance
- **SSD Journals**: Ceph journals on SSD
- **Multiple OSDs**: Multiple OSDs per host
- **Network Tuning**: 10GbE for storage traffic

### Network Performance
- **Dedicated Networks**: Separate storage and VM traffic
- **NUMA Awareness**: CPU/memory locality
- **SR-IOV**: Direct hardware access for high-performance VMs

### Application Performance
- **Resource Requests/Limits**: Proper resource allocation
- **Node Affinity**: Workload placement optimization
- **PodDisruptionBudgets**: Minimize service impact during updates