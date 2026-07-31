# Talos Kubernetes Ansible Playbooks

This directory contains Ansible playbooks for managing Talos Linux Kubernetes clusters on Proxmox infrastructure.

## Prerequisites

1. **Talos VMs**: Proxmox VMs running Talos Linux
2. **Network Access**: Ansible controller must reach Talos nodes on port 50000
3. **Installation**: `talosctl` will be automatically installed by the playbooks

## Available Playbooks

### 01-provision-vms.yml
Create Talos VMs on Proxmox infrastructure with dedicated VLAN and static IPs.

```bash
ansible-playbook playbooks/talos/01-provision-vms.yml
```

**What it does:**
- Downloads latest Talos ISO to Proxmox
- Creates dedicated VLAN bridge for Talos network isolation
- Provisions VMs with optimal settings for Talos/Kubernetes
- Configures static IP addresses in dedicated subnet
- Starts VMs and waits for Talos API availability

**VM Specifications:**
- **Control Plane**: 4 CPU, 4GB RAM, 50GB disk (configurable)
- **Workers**: 2 CPU, 8GB RAM, 100GB disk (configurable)
- **Network**: Isolated VLAN with static IPs
- **Storage**: Uses Proxmox local-lvm by default

### 02-cluster-create.yml
Bootstrap a new Talos Kubernetes cluster.

```bash
ansible-playbook playbooks/talos/02-cluster-create.yml
```

**What it does:**
- Installs `talosctl` on the control machine
- Generates cluster secrets if not present
- Creates machine configurations for all nodes
- Applies configurations and bootstraps Kubernetes
- Generates kubeconfig file

### add-node.yml
Add new nodes to an existing cluster.

```bash
# Add specific nodes
ansible-playbook playbooks/talos/add-node.yml -e "new_nodes=['talos-worker-03','talos-worker-04']"
```

**Requirements:**
- Existing cluster secrets (from 02-cluster-create.yml)
- New nodes defined in inventory

### health-check.yml
Comprehensive cluster health verification.

```bash
ansible-playbook playbooks/talos/health-check.yml
```

**Checks:**
- Talos node connectivity and health
- Kubernetes API server status
- Node readiness and system pods
- etcd health (control plane nodes)
- Kubelet service status

### upgrade.yml
Upgrade Talos and Kubernetes versions.

```bash
# Standard upgrade (with confirmation)
ansible-playbook playbooks/talos/upgrade.yml

# Automated upgrade
ansible-playbook playbooks/talos/upgrade.yml -e auto_approve=true

# Upgrade with custom settings
ansible-playbook playbooks/talos/upgrade.yml -e "preserve=true staged=false"
```

**Options:**
- `preserve`: Preserve user data during upgrade (default: true)
- `staged`: Stage upgrade for next reboot (default: true)  
- `auto_approve`: Skip confirmation prompt (default: false)
- `worker_upgrade_batch_size`: Worker nodes to upgrade simultaneously (default: 1)

### Removing VMs
VM teardown is handled by the shared playbook one level up:

```bash
# Remove all Talos VMs (with confirmation)
ansible-playbook playbooks/remove-vms.yml

# Force removal without confirmation
ansible-playbook playbooks/remove-vms.yml -e "force=true"
```

**⚠️ Warning**: This permanently destroys VMs and their data!

## Configuration

### Inventory Setup
Add Talos nodes to your inventory:

```yaml
# inventory.yaml
all:
  children:
    talos_controlplane:
      hosts:
        talos-cp-01:
          ansible_host: 192.168.100.201
          vm_id: 201
        talos-cp-02:
          ansible_host: 192.168.100.202
          vm_id: 202
        talos-cp-03:
          ansible_host: 192.168.100.203
          vm_id: 203
    talos_worker:
      hosts:
        talos-worker-01:
          ansible_host: 192.168.100.211
          vm_id: 211
        talos-worker-02:
          ansible_host: 192.168.100.212
          vm_id: 212
```

### Variables
Configure Talos settings in `vars.yml`:

See `vars.yml.example` for the full list:

```yaml
# Kubernetes
kubernetes_dns_domain: "cluster.local"
kubernetes_cni: "cilium"   # or "flannel" — see spec 0016
kubernetes_install_disk: "/dev/sda"

# Talos cluster
talos_cluster_name: "talos-homelab"
talos_vip: "192.168.100.200"                          # etcd-elected control plane VIP
talos_cluster_endpoint: "https://192.168.100.200:6443"
talos_pod_subnet: "10.244.0.0/16"
talos_service_subnet: "10.96.0.0/12"

# Proxmox VM provisioning
vm_vlan_id: 100
vm_bridge_name: "vmbr1"
vm_gateway: "192.168.100.1"
vm_subnet: "192.168.100.0/24"
vm_storage: "local-lvm"

# VM specifications
vm_cp_cores: 4
vm_cp_memory: 4096
vm_cp_disk_size: "50G"
vm_worker_cores: 2
vm_worker_memory: 8192
vm_worker_disk_size: "100G"

dns_servers:
  - "1.1.1.1"
  - "8.8.8.8"
ntp_servers:
  - "pool.ntp.org"
```

VMs are placed round-robin across the Proxmox nodes; pin a VM to a specific
node with a `proxmox_node: pve2` hostvar in the inventory.

## File Locations

Relative to the repository root:

- **Machine configs**: `infrastructure/linux/talos/generated/`
- **Kubeconfig / talosconfig**: `infrastructure/linux/talos/generated/`
- **Cluster secrets**: `infrastructure/linux/talos/secrets.yaml` (gitignored — never commit)
- **Version management**: `infrastructure/linux/talos/versions.yaml`

## GitOps Integration

Versions are managed through Renovate in `infrastructure/linux/talos/versions.yaml`:

```yaml
talos:
  installer: "v1.13.7"  # Updated by Renovate
kubernetes:
  version: "v1.36.3"    # Updated by Renovate
```

## Workflow Example

```bash
# 1. Provision VMs on Proxmox
ansible-playbook playbooks/talos/01-provision-vms.yml

# 2. Create initial cluster
ansible-playbook playbooks/talos/02-cluster-create.yml

# 3. Verify health
ansible-playbook playbooks/talos/health-check.yml

# 4. Add workers (optional)
ansible-playbook playbooks/talos/add-node.yml -e "new_nodes=['worker-03']"

# 5. Upgrade when Renovate updates versions
git pull  # Get Renovate updates
ansible-playbook playbooks/talos/upgrade.yml
```

## Troubleshooting

### Common Issues

**"Connection refused" on port 50000**
- Ensure VMs are properly booted with Talos
- Check firewall settings
- Verify network connectivity

**"No such file or directory: secrets.yaml"**
- Run `02-cluster-create.yml` first to generate secrets
- Ensure secrets file isn't accidentally deleted

**"Kubernetes API not ready"**
- Wait longer for bootstrap (can take 5+ minutes)
- Check control plane node health
- Verify network configuration

### Manual Operations

```bash
# Show cluster status
talosctl --nodes 192.168.1.201 health

# Get kubeconfig
talosctl --nodes 192.168.1.201 kubeconfig

# Check services
talosctl --nodes 192.168.1.201 services

# Emergency cluster reset (destructive!)
talosctl --nodes 192.168.1.201 reset --graceful=false
```

## Security Notes

- **secrets.yaml**: Contains sensitive cluster keys - never commit to version control
- **kubeconfig**: Provides full cluster access - store securely
- **Machine configs**: May contain sensitive data - review before sharing
- Consider using Ansible Vault for sensitive variables