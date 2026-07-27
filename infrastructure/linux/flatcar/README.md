# Flatcar Container Linux Configuration

This directory contains Flatcar Container Linux Ignition configurations and templates for the homelab Kubernetes cluster.

## Directory Structure

```
infrastructure/linux/flatcar/
├── versions.yaml              # Version management for Renovate
├── generated/                 # Generated Ignition configs (gitignored)
├── templates/
│   ├── controlplane.yaml.j2   # Control plane Ignition config template
│   ├── worker.yaml.j2          # Worker node Ignition config template
│   └── cloud-init-flatcar.yaml.j2  # Cloud-init template for initial setup
└── README.md                   # This file
```

## Version Management

The [versions.yaml](versions.yaml) file tracks Flatcar and Kubernetes versions:

- **Flatcar release channel**: stable, beta, or alpha channel
- **Flatcar version**: Current version in the chosen channel
- **Kubernetes version**: Must be compatible with containerd version
- **Container runtime**: containerd provided by Flatcar
- **CNI versions**: For network plugin management

These versions are automatically updated by Renovate when new releases are available.

## Ignition Configuration Templates

### controlplane.yaml.j2
Jinja2 template for Flatcar control plane nodes. Includes:
- Kubernetes control plane components (kubeadm, kubelet, kubectl)
- containerd configuration
- Network and storage setup
- systemd units for cluster services
- User and SSH configuration

### worker.yaml.j2  
Jinja2 template for Flatcar worker nodes. Includes:
- Kubelet configuration
- containerd runtime setup
- Network configuration
- systemd units for node services
- Join token configuration

### cloud-init-flatcar.yaml.j2
Template for initial cloud-init configuration:
- Basic system setup
- User account creation
- SSH key deployment
- Network configuration
- Package updates

## Usage with Ansible

These templates are processed by Ansible playbooks in `/infrastructure/ansible/playbooks/flatcar/`:

- `01-provision-vms.yml`: Provisions Flatcar VMs on Proxmox
- `02-cluster-bootstrap.yml`: Bootstraps Kubernetes cluster using kubeadm
- `update.yml`: Performs rolling updates with node draining

## Update Strategy

Flatcar uses automatic updates by default. The update playbook coordinates updates with Kubernetes:

1. **Cordon node**: Prevent new pods from being scheduled
2. **Drain node**: Gracefully evict existing pods
3. **Reboot**: Allow Flatcar to update and reboot
4. **Uncordon**: Re-enable scheduling on the updated node

This ensures zero-downtime cluster updates.