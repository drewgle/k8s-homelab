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

### provision-vms.yml

Provisions Flatcar Container Linux VMs on Proxmox.

**Usage:**
```bash
ansible-playbook playbooks/flatcar/provision-vms.yml
```

**What it does:**
- Downloads Flatcar Container Linux ISO if needed
- Creates control plane and worker VMs with specified resources
- Configures network settings (VLAN, static IPs)
- Applies Ignition configurations for initial setup
- Starts VMs and waits for SSH connectivity

**Configuration:**
- VM specifications in `vars.yml` (`flatcar_*_cores`, `flatcar_*_memory`, etc.)
- Network settings (`flatcar_vlan_id`, `flatcar_gateway`, etc.)
- Node definitions in inventory groups

### cluster-bootstrap.yml

Bootstraps a Kubernetes cluster on provisioned Flatcar nodes.

**Usage:**
```bash
ansible-playbook playbooks/flatcar/cluster-bootstrap.yml
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
   ansible-playbook playbooks/flatcar/provision-vms.yml
   ```

2. **Bootstrap Kubernetes cluster:**
   ```bash
   ansible-playbook playbooks/flatcar/cluster-bootstrap.yml
   ```

3. **Configure kubectl:**
   ```bash
   # Copy the generated kubeconfig
   cp infrastructure/generated/flatcar-kubeconfig-*.yaml ~/.kube/config
   
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
  ansible-playbook playbooks/talos/provision-vms.yml
  ```

## Network Configuration

Flatcar and Talos VMs share the same network configuration:
- **VLAN ID:** 100 (configurable via `flatcar_vlan_id`)
- **IP Range:** 192.168.100.201-203 (control plane), 192.168.100.211-213 (workers)
- **Gateway:** 192.168.100.1
- **Bridge:** vmbr1 (configurable via `flatcar_bridge_name`)

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
- `/tmp/flatcar-cloud-init-*.yaml` - Cloud-init configs
- `/tmp/flatcar-ignition-*.yaml` - Ignition configs
- `infrastructure/generated/flatcar-kubeconfig-*.yaml` - Cluster access config

Temporary files are cleaned up automatically by the remove-vms.yml playbook.