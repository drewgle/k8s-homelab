# Talos Linux Configuration

This directory contains Talos Linux machine configurations and templates for the homelab Kubernetes cluster.

## Directory Structure

```
infrastructure/linux/talos/
├── versions.yaml              # Version management for Renovate
├── generated/                 # Generated machine configs (gitignored)
├── templates/
│   ├── controlplane.yaml.j2   # Control plane machine config template
│   ├── worker.yaml.j2          # Worker machine config template
│   └── secrets.yaml.j2         # Cluster secrets template
└── README.md                   # This file
```

## Version Management

The [versions.yaml](versions.yaml) file tracks Talos and Kubernetes versions:

- **Talos installer version**: Used for OS installation and upgrades
- **Kubernetes version**: Must be compatible with Talos version  
- **CNI versions**: For reference (managed by Talos)

These versions are automatically updated by Renovate when new releases are available.

## Machine Configuration Templates

### controlplane.yaml.j2
Jinja2 template for Talos control plane nodes. Includes:
- Kubernetes control plane components
- etcd configuration 
- Cluster certificates and secrets
- Network and storage configuration

### worker.yaml.j2  
Jinja2 template for Talos worker nodes. Includes:
- Kubelet configuration
- Cluster connection details
- Network configuration
- Node labels and taints

### secrets.yaml.j2
Template for cluster secrets and certificates:
- Machine tokens and CA certificates
- Cluster secrets and bootstrap tokens  
- Service account keys
- etcd certificates

## Generated Files

The `generated/` directory contains:
- Rendered machine configurations for each node
- Kubeconfig file for cluster access
- Applied configurations with actual values

**⚠️ Security Note**: Generated files may contain sensitive data and are excluded from version control.

## Usage

Machine configurations are generated and applied via Ansible playbooks in [../ansible/playbooks/talos/](../ansible/playbooks/talos/).

1. **Generate configs**: Templates are rendered with inventory variables
2. **Apply configs**: Machine configs are applied to Talos nodes via `talosctl`
3. **Bootstrap cluster**: First control plane node bootstraps Kubernetes
4. **Join nodes**: Additional nodes join the cluster automatically

## Integration

- **Ansible**: Playbooks in `../ansible/playbooks/talos/` manage the cluster lifecycle
- **Renovate**: Automatically updates versions in `versions.yaml`
- **Proxmox**: VMs are provisioned on Proxmox infrastructure
- **GitOps**: All configuration managed through Git commits

## Security Considerations

- **secrets.yaml**: Never commit to version control (contains cluster keys)
- **generated/**: Contains applied configurations with sensitive data
- **kubeconfig**: Provides full cluster administrative access
- Use Ansible Vault or external secret management for production deployments

## Related Documentation

- [Talos Ansible Playbooks](../ansible/playbooks/talos/README.md)
- [Talos Official Documentation](https://www.talos.dev/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)