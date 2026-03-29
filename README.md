# HomeLab Infrastructure Automation

> **Modern, automated homelab infrastructure as code with Proxmox, Ceph, and Talos Kubernetes**

This repository contains comprehensive automation for building and maintaining a production-ready homelab infrastructure using modern DevOps practices and GitOps workflows.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    HomeLab Infrastructure                    │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │     Proxmox     │  │      Ceph       │  │  Talos K8s     │ │
│  │   Hypervisor    │  │   Storage       │  │   Clusters     │ │
│  │                 │  │                 │  │                │ │
│  │ • VM Management │  │ • Distributed   │  │ • Secure K8s   │ │
│  │ • Clustering    │  │ • Block Storage │  │ • GitOps Ready │ │
│  │ • Hardening     │  │ • High Avail.   │  │ • Auto Updates │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

## 📁 Project Structure

```
📂 homelabTalk/
├── 📁 infrastructure/           # Infrastructure as Code (IaC)
│   ├── 📁 ansible/             # Ansible automation playbooks
│   │   ├── 📁 playbooks/       
│   │   │   ├── 📁 proxmox/     # Proxmox cluster & hardening
│   │   │   └── 📁 talos/       # Talos Kubernetes lifecycle
│   │   ├── inventory.yaml      # Infrastructure inventory
│   │   ├── vars.yml           # Global configuration
│   │   └── site.yml           # Main orchestration playbook
│   ├── 📁 linux/              # OS configurations & templates
│   │   └── 📁 talos/          # Talos Linux configs
│   │       ├── 📁 templates/  # Machine configuration templates  
│   │       └── versions.yaml  # Version management (Renovate)
│   └── 📁 docs/              # Infrastructure documentation
├── 📁 applications/            # Application deployments
│   ├── 📁 kubernetes/         # K8s manifests & Helm charts
│   ├── 📁 docker-compose/     # Standalone container apps
│   └── 📁 configs/           # Application configurations
├── 📁 docs/                   # Project documentation
│   ├── 📁 architecture/       # System design & decisions
│   ├── 📁 runbooks/          # Operational procedures
│   └── 📁 presentations/     # Talks & demos
├── 📁 scripts/               # Utility scripts & automation
└── renovate.json             # Automated dependency updates
```

## 🚀 Quick Start

### Prerequisites
- **Ansible** 2.12+ with `community.general` and `ansible.posix` collections
- **Proxmox VE** 7.0+ cluster with API access
- **SSH access** to all target nodes
- **Python 3.8+** and required dependencies

### 1. Configuration Setup

```bash
# Clone repository
git clone <repository-url>
cd homelabTalk

# Configure infrastructure variables
cp infrastructure/ansible/vars.yml.example infrastructure/ansible/vars.yml
# Edit vars.yml with your environment details

# Set up inventory
cp infrastructure/ansible/inventory.yaml.example infrastructure/ansible/inventory.yaml  
# Configure your hosts and credentials
```

### 2. Infrastructure Deployment

```bash
cd infrastructure/ansible

# Deploy complete infrastructure stack
ansible-playbook site.yml

# Or deploy specific components:
ansible-playbook playbooks/proxmox/cluster-create.yml    # Proxmox clustering
ansible-playbook playbooks/proxmox/ceph-deploy.yml       # Ceph storage  
ansible-playbook playbooks/talos/provision-vms.yml       # Provision Talos VMs
ansible-playbook playbooks/talos/cluster-create.yml      # Create K8s cluster
```

### 3. Application Deployment

```bash
# Deploy applications to Kubernetes
kubectl apply -k applications/kubernetes/

# Or use Docker Compose for standalone services
docker-compose -f applications/docker-compose/monitoring.yml up -d
```

## 🔧 Core Components

### Infrastructure Automation
- **[Proxmox VE](infrastructure/ansible/playbooks/proxmox/)**: Hypervisor clustering, hardening & management
- **[Ceph Storage](infrastructure/ansible/playbooks/proxmox/ceph/)**: Distributed block storage with HA
- **[Talos Kubernetes](infrastructure/ansible/playbooks/talos/)**: Immutable K8s with security & automation

### Key Features
- 🔒 **Security First**: Hardened configurations, minimal attack surface
- 📦 **GitOps Ready**: Version controlled, reproducible deployments  
- 🔄 **Auto Updates**: Renovate integration for dependency management
- 📊 **Observability**: Built-in monitoring and logging capabilities
- 📚 **Documentation**: Comprehensive guides and runbooks

## 📖 Documentation

| Topic | Description | Link |
|-------|-------------|------|
| **Architecture** | System design and component relationships | [docs/architecture/](docs/architecture/) |
| **Proxmox** | Hypervisor setup, clustering, and hardening | [infrastructure/ansible/playbooks/proxmox/](infrastructure/ansible/playbooks/proxmox/) |
| **Talos** | Kubernetes lifecycle and configuration | [infrastructure/ansible/playbooks/talos/](infrastructure/ansible/playbooks/talos/) |
| **Ceph** | Distributed storage deployment and management | [infrastructure/ansible/playbooks/proxmox/ceph/](infrastructure/ansible/playbooks/proxmox/ceph/) |
| **Runbooks** | Operational procedures and troubleshooting | [docs/runbooks/](docs/runbooks/) |

## 🛠️ Common Operations

### Health Checks
```bash
# Check infrastructure health
ansible-playbook infrastructure/ansible/playbooks/proxmox/health-check.yml
ansible-playbook infrastructure/ansible/playbooks/talos/health-check.yml

# Verify Ceph storage
ansible-playbook infrastructure/ansible/playbooks/proxmox/verify-ceph.yml
```

### Updates & Maintenance
```bash
# Update Talos cluster
ansible-playbook infrastructure/ansible/playbooks/talos/upgrade.yml

# Expand Ceph storage
ansible-playbook infrastructure/ansible/playbooks/proxmox/ceph-expand.yml
```

### Scaling Operations
```bash
# Add Proxmox node to cluster
ansible-playbook infrastructure/ansible/playbooks/proxmox/cluster-add-node.yml

# Add Kubernetes worker nodes  
ansible-playbook infrastructure/ansible/playbooks/talos/add-node.yml
```

## 🔐 Security Considerations

- **Hardened Configurations**: All components use security best practices
- **Minimal Attack Surface**: Talos provides immutable, minimal Linux
- **Automated Updates**: Renovate keeps dependencies current
- **Secrets Management**: Sensitive data handled securely (see `.gitignore`)

## 🤝 Contributing

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🎯 Project Goals

This homelab infrastructure demonstrates:
- **Modern DevOps practices** in a homelab context
- **Infrastructure as Code** with Ansible automation
- **GitOps workflows** for reproducible deployments
- **Enterprise-grade** technologies at homelab scale
- **Security-focused** configuration and hardening

---

**Built with ❤️ for the homelab community**