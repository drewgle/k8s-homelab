# Ceph Storage Cluster Setup

This directory contains modular Ansible playbooks for setting up and managing a Ceph distributed storage cluster on your Proxmox VE nodes.

## Playbook Structure

The Ceph setup is now split into modular playbooks for better maintainability:

### Master Playbooks

- **`04-ceph-deploy.yml`** - Complete initial cluster deployment
- **`ceph-expand.yml`** - Add nodes/storage to existing cluster

### Individual Component Playbooks (`ceph/` folder)

- **`01-common.yml`** - Common setup tasks (packages, user, directories)
- **`02-cluster-init.yml`** - Initialize new cluster (monitors, managers, pools)
- **`add-node.yml`** - Add nodes to existing cluster
- **`03-osd-add.yml`** - Add storage disks as OSDs
- **`status.yml`** - Comprehensive health checks and monitoring

## Prerequisites

### Minimum Requirements

- **3+ Proxmox VE nodes** (for proper quorum and replication)
- **Additional storage disks** on each node (beyond the OS disk)
- **Dedicated network interfaces** (recommended for cluster traffic)
- **At least 4GB RAM** per node for Ceph services
- **Fast network** (1Gbps minimum, 10Gbps recommended)

### Network Planning

Ceph uses two networks:

- **Public Network**: Client access to the cluster (usually your management network)
- **Cluster Network**: Internal Ceph traffic (replication, heartbeat, recovery)

For best performance, use separate networks, but they can be the same for smaller setups.

## Configuration

### 1. Update vars.yml

Configure your network settings in `vars.yml`:

```yaml
# Network configuration
ceph_public_network: "192.168.1.0/24"      # Your management network  
ceph_cluster_network: "10.0.1.0/24"        # Dedicated cluster network (optional)
```

### 2. Storage Planning

**Important**: The playbook will automatically detect and use available disks (non-boot disks without mount points).

- Ensure you have additional disks on each node beyond the OS disk
- All data on these disks will be **permanently destroyed**
- Consider using SSDs for better performance

### 3. Network Setup (Optional but Recommended)

For optimal performance, configure a dedicated cluster network:

```bash
# Example: Configure cluster network interface on each node
# Replace with your actual interface and IP range
ip addr add 10.0.1.x/24 dev eth1  # where x = node number
```

## Deployment

### 1. Run Initial Proxmox Setup First

Ensure your Proxmox nodes are configured:

```bash
ansible-playbook -k playbooks/proxmox/01-initial-setup.yml
```

### 2. Deploy Ceph Cluster (Initial Setup)

```bash
ansible-playbook playbooks/proxmox/04-ceph-deploy.yml
```

The deployment runs these phases automatically:

1. **Common setup** - Packages, users, directories
2. **Cluster initialization** - Monitors, authentication, pools  
3. **OSD creation** - Storage disk detection and configuration
4. **Status validation** - Health checks and cluster verification

### 3. Adding Nodes to Existing Cluster

To add more nodes to an existing Ceph cluster:

1. **Add new hosts to inventory.yaml**:

   ```yaml
   proxmox:
     hosts:
       pve1: { ansible_host: 192.168.1.101 }  # existing
       pve2: { ansible_host: 192.168.1.102 }  # existing  
       pve3: { ansible_host: 192.168.1.103 }  # existing
       pve4: { ansible_host: 192.168.1.104 }  # new node
       pve5: { ansible_host: 192.168.1.105 }  # new node
   ```

2. **Run initial Proxmox setup on new nodes**:

   ```bash
   ansible-playbook playbooks/proxmox/01-initial-setup.yml --limit pve4,pve5
   ```

3. **Add nodes to Ceph cluster**:

   ```bash
   ansible-playbook playbooks/proxmox/ceph-expand.yml
   ```

**What happens during expansion:**

- ✅ Installs Ceph packages on new nodes only (`pveceph install`)
- ✅ Configuration and keyrings arrive automatically via the Proxmox
  cluster filesystem (`/etc/pve`) — nothing is copied by hand
- ✅ Tops monitors/managers back up to 3 if the cluster is below that
- ✅ Automatically detects and adds new OSDs from available disks
- ✅ Does NOT recreate pools or cluster settings
- ✅ Shows rebalancing progress and final cluster status

**Prerequisite:** new nodes must already be Proxmox cluster members
(`cluster-add-node.yml`) — pveceph operates through the cluster filesystem.

### Individual Component Operations

For advanced operations, you can run individual playbooks:

```bash
# Add OSDs to existing nodes only
ansible-playbook playbooks/proxmox/ceph/03-osd-add.yml

# Comprehensive status check
ansible-playbook playbooks/proxmox/ceph/status.yml

# Setup common components only (packages, directories)
ansible-playbook playbooks/proxmox/ceph/01-common.yml
```

### 3. Verify Installation

The playbook will show cluster status at the end, but you can also check manually:

```bash
# SSH to any Proxmox node and run:
ceph -s                    # Cluster status
ceph health               # Health check
ceph osd tree             # OSD layout
ceph df                   # Storage usage
```

**Automated Verification**: Use the included verification playbook:

```bash
# Run from ansible control machine
ansible-playbook playbooks/proxmox/verify-ceph.yml

# For detailed output (optional)
ansible-playbook playbooks/proxmox/verify-ceph.yml -e show_detailed=true

# Check specific nodes only
ansible-playbook playbooks/proxmox/verify-ceph.yml --limit node1,node2
```

## What the Playbook Does

Everything runs through `pveceph`, Proxmox's supported Ceph tooling, so the
result is fully visible and manageable in the PVE web UI's Ceph panel:

1. **Installs Ceph** on all nodes (`pveceph install --repository no-subscription`)
2. **Initializes the cluster config** with proper networking (`pveceph init`;
   config and keyrings live in `/etc/pve` and replicate to every node)
3. **Creates monitors and managers** on the first 3 nodes (`pveceph mon/mgr create`)
4. **Detects and creates OSDs** from unused disks (`pveceph osd create`)
5. **Creates the default RBD pool** (size 3, min_size 2, autoscaled PGs) and
   **registers it as Proxmox storage** automatically (`--add_storages`)

## Post-Installation

### Proxmox Integration

Nothing manual to do: `--add_storages` already registered the pool as a
Proxmox RBD storage (named after the pool, default `rbd`), and the cluster
is manageable from any node's web UI under **Node → Ceph**. To use it for
Kubernetes VM disks, set `vm_storage: "rbd"` in `vars.yml`.

## Troubleshooting

### Common Issues

**Initial Setup Issues:**

- Check network connectivity between nodes
- Verify firewall allows Ceph ports (6789, 6800-7300)
- Ensure time synchronization between nodes

**Node Addition Issues:**

- `Failed to connect to existing cluster`: Check that at least one monitor node is running
- `Permission denied accessing keyrings`: Verify SSH access and file permissions on existing nodes
- `OSDs not being added`: Check that new disks are not mounted and have no partitions
- `Cluster shows HEALTH_WARN after adding nodes`: This is normal during rebalancing, monitor with `ceph -w`

**General Issues:**

- `HEALTH_WARN clock skew` → Sync time with NTP
- `HEALTH_WARN too few PGs` → Increase PG count for pools  
- `HEALTH_WARN pool has many more objects per pg` → Add more OSDs
- `Slow performance after adding nodes` → Wait for rebalancing to complete (can take hours)

### Useful Commands

```bash
# Check cluster status
ceph -s

# Monitor cluster events 
ceph -w

# Check OSD status
ceph osd tree
ceph osd stat

# Pool management
ceph osd pool ls detail
ceph osd pool create <pool_name> <pg_num>

# Dashboard management
ceph mgr module ls
ceph dashboard create-self-signed-cert
```

### Log Locations

- **Ceph logs**: `/var/log/ceph/`
- **Service status**: `systemctl status ceph-mon@<node>`
- **Configuration**: `/etc/ceph/ceph.conf`

## Safety Considerations

⚠️  **WARNING**: This setup will:

- **Destroy all data** on non-boot disks
- **Modify system network configuration**
- **Install cluster software** that affects system resources

🔄 **Backup Strategy**:

- The playbook creates configuration backups
- Document your network setup before running
- Test recovery procedures after setup

## Performance Tuning

For production use, consider:

1. **SSD journals** or **NVMe OSDs** for better performance
2. **10Gbps networking** for cluster traffic  
3. **Separate cluster and public networks**
4. **Tune PG counts** based on OSD count and data size
5. **Configure CRUSH maps** for rack/host failure domains

## Scaling

### Adding More Nodes

The playbooks support adding nodes to an existing cluster seamlessly:

1. **Add new hosts to inventory.yaml**
2. **Ensure new nodes have Proxmox installed and SSH access configured**
3. **Run the Ceph expansion playbook** - it will automatically detect the existing cluster

```bash
# Add new nodes to inventory, then run:
ansible-playbook playbooks/proxmox/ceph-expand.yml
```

### Adding More OSDs

To add more OSDs to existing nodes:

1. **Add physical disks** to your existing Proxmox nodes
2. **Run the OSD playbook** - it will detect and configure new disks automatically

```bash
ansible-playbook playbooks/proxmox/ceph/03-osd-add.yml
```

### Monitor Addition (Advanced)

The playbooks maintain 3 monitor nodes by default. To add more monitors manually:

```bash
# SSH to the target node and run:
pveceph mon create
```

**Note**: More than 5 monitors can impact performance. Odd numbers (3, 5) are recommended for quorum.
