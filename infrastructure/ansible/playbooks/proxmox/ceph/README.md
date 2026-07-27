# Ceph Modular Playbooks

This folder contains individual Ceph component playbooks that can be run independently or as part of the master deployment workflows.

## Individual Playbooks

### `01-common.yml`
**Purpose**: Common setup tasks for all nodes  
**Use case**: Prepare nodes for Ceph installation  
**Run when**: Before any Ceph operations, or to refresh package installation

```bash
ansible-playbook ceph/01-common.yml
```

**What it does:**
- Validates minimum node requirements (3+) and Proxmox cluster membership
- Installs Ceph via `pveceph install --repository no-subscription`

---

### `02-cluster-init.yml`  
**Purpose**: Initialize a new Ceph cluster  
**Use case**: First-time cluster setup on 3+ nodes  
**Run when**: No Ceph cluster exists yet

```bash
ansible-playbook ceph/02-cluster-init.yml
```

**What it does:**
- `pveceph init` with the public/cluster networks from vars.yml
  (config and keyrings live in `/etc/pve`, shared cluster-wide automatically)
- Creates monitors and managers on the first three nodes (`pveceph mon/mgr create`)
- Creates the RBD pool (size 3, min_size 2, autoscaled PGs) and registers it
  as Proxmox storage (`--add_storages`)

⚠️  **Warning**: Only run on new installations. Will fail if cluster already exists.

---

### `add-node.yml`
**Purpose**: Add new nodes to existing cluster  
**Use case**: Expanding cluster with additional nodes  
**Run when**: Adding nodes to a running cluster

```bash
ansible-playbook ceph/add-node.yml
```

**What it does:**
- Installs Ceph packages on nodes that lack them (config/keyrings arrive
  automatically via the Proxmox cluster filesystem)
- Tops the monitor/manager count back up to 3 if below (e.g. after starting
  with fewer nodes) — otherwise creates none
- Validates cluster health afterwards

---

### `03-osd-add.yml`
**Purpose**: Add storage disks as OSDs  
**Use case**: Adding storage capacity to any nodes  
**Run when**: New disks are available or cluster needs more storage

```bash
ansible-playbook ceph/03-osd-add.yml
```

**What it does:**
- Detects available whole disks on all nodes (unmounted, exactly not `sda`)
- Filters out disks already used by Ceph (`ceph-volume lvm list`)
- Creates OSDs with `pveceph osd create` (destroys data on those disks!)
- Shows the OSD tree and storage utilization after addition

---

### `status.yml` 
**Purpose**: Comprehensive cluster health check  
**Use case**: Monitoring, troubleshooting, status verification  
**Run when**: Regular health checks or after major operations

```bash
ansible-playbook ceph/status.yml  
```

**What it does:**
- Tests connectivity from all nodes
- Gathers cluster status and health details
- Shows OSD tree and storage usage
- Displays pool information
- Provides troubleshooting guidance

## Common Usage Patterns

### Initial 3-node deployment:
```bash
ansible-playbook ceph/01-common.yml
ansible-playbook ceph/02-cluster-init.yml  
ansible-playbook ceph/03-osd-add.yml
ansible-playbook ceph/status.yml
```

### Adding 2 more nodes:
```bash
# Add nodes to inventory first, then:
ansible-playbook ceph/01-common.yml
ansible-playbook ceph/add-node.yml
ansible-playbook ceph/03-osd-add.yml
ansible-playbook ceph/status.yml
```

### Adding storage to existing nodes:
```bash
ansible-playbook ceph/03-osd-add.yml
ansible-playbook ceph/status.yml
```

### Health check and troubleshooting:
```bash
ansible-playbook ceph/status.yml
```

## Master Playbooks (Recommended)

For most use cases, use the master playbooks in the parent directory:
- `../04-ceph-deploy.yml` - Complete initial deployment
- `../ceph-expand.yml` - Add nodes and storage to existing cluster

These orchestrate the individual playbooks in the correct order with proper error handling.