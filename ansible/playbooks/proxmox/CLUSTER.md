# Proxmox VE Clustering

These playbooks manage Proxmox VE cluster creation and expansion for high availability and centralized management.

## Overview

Proxmox clustering enables:

- **High Availability (HA)** - Automatic VM failover between nodes
- **Live Migration** - Move running VMs between nodes without downtime  
- **Centralized Management** - Single web interface for the entire cluster
- **Shared Configuration** - Consistent settings and user accounts across all nodes
- **Resource Pooling** - Aggregate compute and storage resources

## Prerequisites

### Minimum Requirements

- **2+ Proxmox VE nodes** (3+ recommended for HA)
- **Network connectivity** between all nodes (same subnet preferred)  
- **Synchronized time** across all nodes (NTP configured)
- **SSH key authentication** between all nodes
- **Matching Proxmox versions** across all nodes
- **Unique node names** and IP addresses

### Network Planning

- All nodes should be on the same network segment
- Ensure ports are open: 22 (SSH), 8006 (Web UI), 5404-5405 (corosync)
- Configure firewall rules to allow cluster communication

## Usage

### Initial Cluster Creation

```bash
# 1. Run initial setup first
ansible-playbook playbooks/proxmox/initial-setup.yml

# 2. Reboot if kernel updates were installed  
ansible-playbook playbooks/proxmox/reboot.yml

# 3. Create the cluster
ansible-playbook playbooks/proxmox/cluster-create.yml
```

### Adding Nodes to Existing Cluster

```bash
# 1. Add new hosts to inventory.yaml
# 2. Setup new nodes
ansible-playbook playbooks/proxmox/initial-setup.yml --limit new-node1,new-node2

# 3. Join them to the cluster
ansible-playbook playbooks/proxmox/cluster-add-node.yml
```

## What the Playbooks Do

### `cluster-create.yml`

- Validates network connectivity between all nodes
- Creates cluster on first node using `pvecm create`  
- Joins remaining nodes to the cluster using `pvecm add`
- Verifies cluster formation and service health
- Enables corosync communication and shared configuration

### `cluster-add-node.yml`

- Detects existing cluster and identifies new nodes
- Validates prerequisites on new nodes
- Joins new nodes to existing cluster non-disruptively
- Updates cluster configuration and verifies health
- Maintains cluster quorum and existing services

## Post-Cluster Setup

### Access the Cluster

After clustering, access the web interface from any node:

- `https://any-node-ip:8006`
- All nodes now share the same authentication and configuration

### Configure High Availability

1. **Shared Storage**: Set up shared storage (NFS, Ceph, iSCSI)
2. **HA Groups**: Configure HA groups in web interface
3. **Fencing**: Set up fencing mechanisms for split-brain protection
4. **Resource Policies**: Define VM placement and migration policies

### Test Cluster Functions

```bash
# Test VM migration
qm migrate <vmid> <target-node>

# Check cluster status  
pvecm status
pvecm nodes

# Monitor cluster logs
journalctl -f -u corosync
```

## Troubleshooting

### Common Issues

**Cluster creation fails:**

- Verify network connectivity: `ping` between all nodes
- Check firewall: ports 22, 5404-5405, 8006 must be open
- Ensure time synchronization: `timedatectl status`
- Verify SSH key authentication works between nodes

**Node fails to join:**

- Check existing cluster is healthy: `pvecm status`
- Verify new node can reach cluster: `ping cluster-node`
- Ensure Proxmox versions match: `pveversion`
- Check for network conflicts or duplicate IPs

**Split-brain scenarios:**

- Ensure odd number of nodes (3, 5, 7) for proper quorum
- Configure fencing mechanisms
- Monitor corosync logs: `journalctl -u corosync`

### Recovery Commands

```bash
# Check cluster quorum
pvecm expected 1    # Temporarily set expected nodes to 1

# Force cluster online (emergency only)
systemctl stop pve-cluster
pmxcfs -l          # Local mode

# Restart cluster services
systemctl restart corosync
systemctl restart pve-cluster
```

### Log Locations

- **Cluster logs**: `/var/log/pve-cluster/`
- **Corosync logs**: `journalctl -u corosync`
- **General Proxmox**: `/var/log/daemon.log`

## Advanced Configuration

### Cluster Networks

For production, consider separate networks:

```yaml
# In vars.yml
proxmox_cluster_network: "10.0.1.0/24"    # Dedicated cluster traffic
```

### Storage Integration

After clustering, configure shared storage:

1. **Ceph**: Use the included Ceph playbooks for distributed storage
2. **NFS**: Mount shared NFS for VM storage
3. **iSCSI**: Configure iSCSI targets for shared block storage

### Backup Configuration

Set up cluster-wide backups:

1. Configure backup retention policies
2. Set up backup schedules for all VMs
3. Test restore procedures regularly

## Security Considerations

- **Encrypt cluster traffic**: Configure corosync encryption
- **Secure API access**: Use HTTPS and strong passwords
- **Network isolation**: Use VLANs to separate cluster traffic
- **Regular updates**: Keep all nodes at the same patch level
- **SSH hardening**: Disable password auth, use key-only authentication
