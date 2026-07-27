# Flatcar Container Linux Playbooks

This directory contains Ansible playbooks for managing Flatcar Container Linux VMs and Kubernetes clusters in your Proxmox homelab.

## Prerequisites

Before using these playbooks, ensure:

1. **Proxmox hosts** are configured and accessible via SSH
2. **vars.yml** contains Flatcar-specific configuration
3. **inventory.yaml** includes flatcar_controlplane and flatcar_worker groups
4. **Network** (VLAN 100) is configured and available
5. **SSH keys** are available on GitHub for your user account

## Playbooks

### 01-provision-vms.yml

Provisions Flatcar Container Linux VMs on Proxmox.

**Usage:**
```bash
ansible-playbook playbooks/flatcar/01-provision-vms.yml
```

**What it does:**
- Downloads Flatcar Container Linux ISO if needed
- Creates control plane and worker VMs with specified resources
- Configures network settings (VLAN, static IPs)
- Applies Ignition configurations for initial setup
- Starts VMs and waits for SSH connectivity

**Configuration:**
- VM specifications in `vars.yml` (`vm_cp_cores`, `vm_worker_memory`, etc.)
- Network settings (`vm_vlan_id`, `vm_gateway`, etc.) — shared with Talos
- Node definitions in inventory groups
- VMs are placed round-robin across Proxmox nodes; pin with a
  `proxmox_node` hostvar in the inventory

### 02-cluster-bootstrap.yml

Bootstraps a Kubernetes cluster on provisioned Flatcar nodes.

**Usage:**
```bash
ansible-playbook playbooks/flatcar/02-cluster-bootstrap.yml
```

**What it does:**
- Initializes Kubernetes cluster on first control plane node using kubeadm
- Joins additional control plane nodes (if any)
- Joins worker nodes to the cluster
- Installs CNI plugin (Flannel or Cilium)
- Configures kubectl access
- Saves kubeconfig for local access

**Prerequisites:**
- VMs must be provisioned and running
- Ignition configuration must have applied successfully
- Kubernetes binaries must be installed

### update.yml

Performs rolling updates of Flatcar nodes with Kubernetes-aware draining.

**Usage:**
```bash
ansible-playbook playbooks/flatcar/update.yml
```

**What it does:**
- Checks for available Flatcar updates
- Cordons nodes to prevent new pod scheduling
- Drains pods gracefully from the node
- Downloads and applies OS updates
- Reboots nodes if required
- Uncordons nodes after successful update
- Verifies cluster health

**Features:**
- Serial execution (one node at a time)
- Automatic node draining and uncordoning
- Update status monitoring
- Cluster health verification

## Unified VM Management

### Remove VMs

Use the unified removal playbook to remove either Talos or Flatcar VMs:

```bash
# Remove all Flatcar VMs
ansible-playbook playbooks/remove-vms.yml -e "vm_type=flatcar"

# Force removal without confirmation
ansible-playbook playbooks/remove-vms.yml -e "vm_type=flatcar" -e "force=true"

# Remove Talos VMs (to switch to Flatcar)
ansible-playbook playbooks/remove-vms.yml -e "vm_type=talos"
```

## Typical Workflow

### Initial Setup
1. **Provision VMs:**
   ```bash
   ansible-playbook playbooks/flatcar/01-provision-vms.yml
   ```

2. **Bootstrap Kubernetes cluster:**
   ```bash
   ansible-playbook playbooks/flatcar/02-cluster-bootstrap.yml
   ```

3. **Configure kubectl:**
   ```bash
   # Copy the generated kubeconfig
   cp infrastructure/linux/flatcar/generated/kubeconfig ~/.kube/config

   # Verify cluster access
   kubectl get nodes
   ```

### Maintenance
- **Update Flatcar nodes:**
  ```bash
  ansible-playbook playbooks/flatcar/update.yml
  ```

- **Switch to Talos:**
  ```bash
  # Remove Flatcar VMs (same IPs will be reused)
  ansible-playbook playbooks/remove-vms.yml -e "vm_type=flatcar"
  
  # Provision Talos VMs
  ansible-playbook playbooks/talos/01-provision-vms.yml
  ```

## Network Configuration

Flatcar and Talos VMs share the same network configuration:
- **VLAN ID:** 100 (configurable via `vm_vlan_id`)
- **IP Range:** 192.168.100.201-203 (control plane), 192.168.100.211-213 (workers)
- **Gateway:** 192.168.100.1 (configurable via `vm_gateway`)
- **Bridge:** vmbr1 (configurable via `vm_bridge_name`)

**Important:** You can only run either Flatcar OR Talos VMs at the same time since they use the same IP addresses. Use the remove-vms.yml playbook to switch between them.

## Troubleshooting

### VM Provisioning Issues
- Check Proxmox cluster status: `pvecm status`
- Verify ISO download: Check `/var/lib/vz/template/iso/`
- Review VM creation logs in Ansible output
- Ensure storage has sufficient space

### Cluster Bootstrap Issues
- Verify SSH connectivity to all nodes
- Check Ignition config application in VM console
- Ensure Kubernetes binaries are installed: `ls /opt/bin/`
- Review kubeadm logs: `journalctl -u kubelet`

### Update Issues
- Check update engine status: `update_engine_client -status`
- Verify cluster connectivity before updates
- Ensure sufficient time for pod draining
- Monitor cluster health during updates

### Network Issues
- Verify VLAN configuration on Proxmox
- Check bridge settings: `ip link show vmbr1`
- Test connectivity between nodes
- Verify DNS resolution

## Files Generated

During execution, these files are created:
- `/var/lib/vz/snippets/flatcar-cloud-init-*.yaml` - Cloud-init configs (on each VM's Proxmox node)
- `/var/lib/vz/snippets/flatcar-ignition-*.yaml` - Ignition configs (on each VM's Proxmox node)
- `infrastructure/linux/flatcar/generated/kubeconfig` - Cluster access config (gitignored)

Snippets are cleaned up automatically by the remove-vms.yml playbook.