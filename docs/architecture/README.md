# Architecture Overview

This document provides a comprehensive overview of the homelab infrastructure architecture, including component relationships, data flows, and design decisions.

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
  - Fault tolerant (n-2 redundancy)
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
- **Networking**: Flannel CNI for pod networking
- **Storage**: Longhorn for persistent volumes

### Application Layer

#### GitOps Management
- **ArgoCD**: Continuous delivery for K8s applications
- **Git Repository**: Single source of truth for configuration

#### Core Services
- **Ingress**: NGINX Ingress Controller with cert-manager
- **Monitoring**: Prometheus + Grafana stack
- **Logging**: Loki for log aggregation
- **Storage**: Longhorn for container persistent volumes

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
(`infrastructure/ansible/playbooks/flatcar/`) for comparison; both use the
same VM network and IP ranges, so only one runs at a time.

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
**Decision**: ArgoCD for application deployment
**Rationale**:
- Git as single source of truth
- Automated drift detection
- Audit trail for all changes
- Simplified rollback procedures

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
- **Container Network**: 10.244.0.0/16 (Pod CIDR)
- **Service Network**: 10.96.0.0/12 (Service CIDR)
- **Storage Network**: 10.0.1.0/24 (optional dedicated Ceph cluster network)

## Security Architecture

### Defense in Depth
1. **Physical Security**: Locked server room/rack
2. **Host Hardening**: CIS benchmarks and security baselines
3. **Network Segmentation**: VLANs and firewall rules
4. **VM Isolation**: Proxmox VM boundaries
5. **Container Security**: Pod security standards
6. **Application Security**: Security policies and scanning

### Access Control
- **SSH Keys**: No password authentication
- **RBAC**: Fine-grained Kubernetes permissions
- **Network Policies**: Micro-segmentation in K8s
- **Service Mesh**: Optional Istio for advanced traffic control

### Secrets Management
- **Ansible Vault**: Encrypted variables for infrastructure
- **Sealed Secrets**: Kubernetes secrets encrypted at rest
- **External Secrets**: Optional HashiCorp Vault integration

## Monitoring and Observability

### Metrics
- **Infrastructure**: Node Exporter, Proxmox Exporter
- **Kubernetes**: kube-state-metrics, cadvisor
- **Applications**: Custom metrics via Prometheus

### Logging
- **Centralized**: Loki for log aggregation
- **Application Logs**: Structured logging with JSON
- **Audit Logs**: Kubernetes API server logs

### Alerting
- **AlertManager**: Route alerts to appropriate channels
- **Grafana**: Visual dashboards and alert rules
- **Notification**: Slack, email, or PagerDuty integration

## Backup and Disaster Recovery

### Data Protection
- **VM Backups**: Proxmox backup server
- **K8s Backups**: Velero for application data
- **Configuration Backups**: Git repository with IaC
- **Storage Replication**: Ceph replication pools

### Recovery Procedures
- **RTO**: Recovery Time Objective < 4 hours
- **RPO**: Recovery Point Objective < 1 hour
- **DR Testing**: Monthly disaster recovery drills
- **Documentation**: Detailed runbooks for all scenarios

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