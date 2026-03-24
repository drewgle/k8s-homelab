# Ceph Modular Playbooks

This folder contains individual Ceph component playbooks that can be run independently or as part of the master deployment workflows.

## Individual Playbooks

### `common.yml`
**Purpose**: Common setup tasks for all nodes  
**Use case**: Prepare nodes for Ceph installation  
**Run when**: Before any Ceph operations, or to refresh package installation

```bash
ansible-playbook ceph/common.yml
```

**What it does:**
- Installs Ceph packages and dependencies
- Creates ceph user and directory structure  
- Validates minimum node requirements
- Checks current cluster configuration status

---

### `cluster-init.yml`  
**Purpose**: Initialize a new Ceph cluster  
**Use case**: First-time cluster setup on 3+ nodes  
**Run when**: No Ceph cluster exists yet

```bash
ansible-playbook ceph/cluster-init.yml
```

**What it does:**
- Generates cluster UUID and authentication keyrings
- Creates and distributes monitor map
- Initializes monitor and manager services
- Creates default storage pools
- Enables dashboard module

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
- Detects existing cluster configuration  
- Copies keyrings and configuration to new nodes
- Updates monitor map with new nodes
- Validates connectivity to existing cluster
- Does NOT create monitors or managers on new nodes

---

### `osd-add.yml`
**Purpose**: Add storage disks as OSDs  
**Use case**: Adding storage capacity to any nodes  
**Run when**: New disks are available or cluster needs more storage

```bash
ansible-playbook ceph/osd-add.yml
```

**What it does:**
- Detects available disks on all nodes
- Filters out already configured OSDs
- Prepares new disks as OSDs
- Triggers cluster rebalancing
- Shows storage utilization after addition

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
ansible-playbook ceph/common.yml
ansible-playbook ceph/cluster-init.yml  
ansible-playbook ceph/osd-add.yml
ansible-playbook ceph/status.yml
```

### Adding 2 more nodes:
```bash
# Add nodes to inventory first, then:
ansible-playbook ceph/common.yml
ansible-playbook ceph/add-node.yml
ansible-playbook ceph/osd-add.yml
ansible-playbook ceph/status.yml
```

### Adding storage to existing nodes:
```bash
ansible-playbook ceph/osd-add.yml
ansible-playbook ceph/status.yml
```

### Health check and troubleshooting:
```bash
ansible-playbook ceph/status.yml
```

## Master Playbooks (Recommended)

For most use cases, use the master playbooks in the parent directory:
- `../ceph-deploy.yml` - Complete initial deployment
- `../ceph-expand.yml` - Add nodes and storage to existing cluster

These orchestrate the individual playbooks in the correct order with proper error handling.