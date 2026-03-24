# Proxmox Homelab Ansible Setup

Automated setup and management for a Proxmox VE homelab with clustering, security hardening, and distributed storage.

## Quick Start

### 1. Configure Environment

```bash
cd ansible

# Create configuration from example
cp vars.yml.example vars.yml

# Update IP addresses in inventory
vim inventory.yaml

# Set required variables  
vim vars.yml
```

**Required in `vars.yml`:**

```yaml
github_username: "your-github-username"     # For SSH key fetching
proxmox_cluster_name: "homelab"            # Cluster name
ceph_public_network: "192.168.1.0/24"      # If using Ceph storage
```

### 2. Deploy Infrastructure

```bash
# Initial setup (uses password, then switches to SSH keys)
ansible-playbook -k playbooks/proxmox/initial-setup.yml

# Security hardening
ansible-playbook playbooks/proxmox/harden.yml

# Create HA cluster
ansible-playbook playbooks/proxmox/cluster-create.yml

# Optional: Deploy Ceph storage
ansible-playbook playbooks/proxmox/ceph-deploy.yml
```

### 3. Verify Deployment

```bash
ansible-playbook playbooks/proxmox/verify-hardening.yml
ansible-playbook playbooks/proxmox/verify-ceph.yml        # if using Ceph
ansible-playbook playbooks/proxmox/health-check.yml
```

## Key Features

- **Initial Setup** - SSH keys, repositories, system updates
- **Security Hardening** - SSH, firewall, fail2ban, kernel parameters
- **HA Clustering** - Proxmox cluster with corosync
- **Distributed Storage** - Ceph cluster integration (optional)
- **Verification** - Automated health and security checks

## File Structure

### Configuration

- `inventory.yaml` - Node IP addresses and connection details
- `vars.yml` - Environment configuration (created from example)
- `vars.yml.example` - Template with required variables

### Main Playbooks

- `initial-setup.yml` - Basic Proxmox setup with SSH keys
- `harden.yml` - Security configuration (SSH, firewall, fail2ban)
- `cluster-create.yml` - Proxmox HA cluster creation
- `cluster-add-node.yml` - Add nodes to existing cluster
- `ceph-deploy.yml` - Complete Ceph storage deployment
- `ceph-expand.yml` - Add storage/nodes to Ceph cluster

### Verification & Health Checks

- `verify-hardening.yml` - Security validation  
- `verify-ceph.yml` - Ceph cluster health
- `health-check.yml` - General system health

### Documentation

- `HARDENING.md` - Security details and troubleshooting
- `CEPH.md` - Ceph storage setup guide
- `CLUSTER.md` - Proxmox clustering guide

## Common Operations

### Scaling

```bash
# Add new nodes to inventory.yaml, then:
ansible-playbook playbooks/proxmox/initial-setup.yml --limit new-node
ansible-playbook playbooks/proxmox/cluster-add-node.yml
```

### Maintenance

```bash
ansible-playbook playbooks/proxmox/health-check.yml     # Check cluster health
ansible-playbook playbooks/proxmox/verify-hardening.yml # Verify security
ansible-playbook playbooks/proxmox/reboot.yml           # Rolling reboots
```

### Debug Commands

```bash
ansible-playbook --check <playbook>        # Dry run
ansible-playbook <playbook> --limit node1  # Single node
ansible all -m ping                        # Test connectivity
```

## Prerequisites  

- Ansible installed on control machine
- SSH access to Proxmox nodes (initially password, then key-based)
- Root access on all nodes
- SSH public keys uploaded to your GitHub account
- Minimum 3 nodes for full HA setup

## Advanced Features

**Individual Ceph Operations**: Use playbooks in `playbooks/proxmox/ceph/` for specific tasks:

- `ceph/common.yml` - Setup packages and directories only
- `ceph/osd-add.yml` - Add storage to existing nodes
- `ceph/status.yml` - Comprehensive health check

**Important**: Read [playbooks/proxmox/CEPH.md](playbooks/proxmox/CEPH.md) first for requirements and network configuration.

## Post-Deployment Validation

After running the playbooks, verify the setup:

1. **SSH Key Access**: SSH to each host without password
2. **GitHub Keys Applied**: Check `/root/.ssh/authorized_keys` contains your GitHub keys
3. **Repository Check**: `apt update` should work without enterprise repo errors
4. **No Subscription Nag**: Access Proxmox web interface - no subscription warning
5. **System Updated**: Check `apt list --upgradable` shows no packages

You can verify your GitHub keys were properly fetched by checking:

```bash
curl -s https://github.com/YOUR_USERNAME.keys
```

## Customization

### Folder Structure

The playbooks are organized by system type:

```
playbooks/
├── proxmox/          # Proxmox VE specific playbooks
│   ├── initial-setup.yml
│   ├── reboot.yml
│   └── health-check.yml
└── [future]/         # Add other system types here
    ├── kubernetes/   # Example: Kubernetes playbooks
    ├── docker/       # Example: Docker host playbooks
    └── networking/   # Example: Network device playbooks
```

### Adding More System Types

To add playbooks for other systems (e.g., Docker, Kubernetes, networking):

1. Create a new subfolder: `mkdir playbooks/docker`
2. Add your playbooks to the new folder
3. Update `site.yml` to include the new playbooks if needed
4. Add new host groups to `inventory.yaml`

### Adding More Packages

Edit the "Install useful packages" task in `playbooks/proxmox/initial-setup.yml` to add more packages as needed.

### Different Debian Versions

The playbook handles both Bullseye (Debian 11) and Bookworm (Debian 12) repositories. It will automatically use the appropriate repository based on the detected OS version.

## Troubleshooting

### Configuration Issues

- Ensure `vars.yml` exists (copy from `vars.yml.example`)
- Verify the GitHub username in `vars.yml` is correct
- Check file permissions on `vars.yml` if you get access denied errors

### SSH Connection Issues

- Ensure your Proxmox hosts are reachable
- Check firewall settings (port 22)
- Verify root login is enabled in SSH config

### GitHub SSH Key Issues

- Verify the GitHub username is correct
- Check that the user has public SSH keys on GitHub: `https://github.com/{username}.keys`
- Ensure the control machine has internet access to fetch keys from GitHub
- If GitHub is unreachable, consider using local SSH keys as backup

### Repository Issues

- Check internet connectivity on Proxmox hosts
- Verify DNS resolution is working
- Check `/etc/apt/sources.list.d/` for conflicting repositories

### Upgrade Issues

- Monitor disk space during upgrades
- Check `/var/log/apt/` for detailed upgrade logs
- Some packages may require manual intervention

## Files Created/Modified

The playbooks will backup original files before modification and create these config files:

- **vars.yml** - Your environment-specific configuration (from vars.yml.example)  
- **inventory.yaml** - Your Proxmox host definitions
- **.gitignore** - Keeps sensitive files out of version control

System files modified on Proxmox hosts:

- `/etc/apt/sources.list.backup`
- `/etc/apt/sources.list.d/pve-enterprise.list.backup`
- `/usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js.backup`
