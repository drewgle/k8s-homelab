# HomeLab Infrastructure Automation

> Automated homelab infrastructure as code: Proxmox, Ceph, and Kubernetes (Talos or Flatcar)

Ansible automation for building and maintaining a homelab that runs Kubernetes
on a Proxmox VE cluster with Ceph storage. Two Kubernetes node operating
systems are supported — Talos Linux and Flatcar Container Linux — sharing the
VM VLAN but addressed separately, so you can run either or both.

## Project Structure

```
k8s-homelab/
├── infrastructure/
│   ├── ansible/                  # All automation
│   │   ├── ansible.cfg
│   │   ├── inventory.yaml        # Proxmox hosts + K8s node definitions
│   │   ├── vars.yml.example      # Copy to vars.yml and customize
│   │   ├── requirements.yml      # Required Ansible collections
│   │   ├── site.yml              # Proxmox stack orchestration
│   │   ├── roles/
│   │   │   └── proxmox_vm/       # Shared VM bridge + create/start tasks
│   │   └── playbooks/
│   │       ├── proxmox/          # Cluster create/add-node, Ceph, hardening
│   │       ├── talos/            # Talos VM + cluster lifecycle
│   │       ├── flatcar/          # Flatcar VM + kubeadm cluster lifecycle
│   │       └── remove-vms.yml    # Tear down Talos or Flatcar VMs
│   └── linux/
│       ├── proxmox/              # Bare-metal PVE auto-install (answer on USB partition)
│       ├── talos/                # Talos machine config templates + versions
│       └── flatcar/              # Flatcar ignition/cloud-init templates + versions
├── applications/                 # Application deployments (planned)
├── docs/
│   ├── architecture/             # System design and decisions
│   ├── presentation/             # Talk materials
│   └── specs/                    # Numbered specs for planned work
└── renovate.json                 # Automated dependency updates
```

## Quick Start

### Prerequisites

- **Ansible** 2.15+ (`pip install ansible`)
- **Helm** on the control machine — the Kubernetes playbooks install the CNI
  with it ([spec 0016](docs/specs/0016-cluster-networking-cilium.md))
- **Proxmox VE** 8.0+ hosts reachable over SSH as root (9.x is what's
  tested — the bare-metal installer pins a 9.x ISO and the repository
  handling covers deb822 sources)
- Collections: `ansible-galaxy collection install -r infrastructure/ansible/requirements.yml`

### 1. Configuration

```bash
cd infrastructure/ansible

# Environment configuration
cp vars.yml.example vars.yml
# Edit vars.yml with your networks, cluster names, and VM sizing

# Edit inventory.yaml with your Proxmox host IPs and K8s node definitions
```

### 2. Bare Metal (optional)

Starting from blank hardware? Build an unattended-install USB stick that
images each node with Proxmox VE and leaves it Ansible-ready (static IP, root
SSH keys) — see [infrastructure/linux/proxmox/](infrastructure/linux/proxmox/):

```bash
ansible-playbook playbooks/bootstrap/01-render-answers.yml
ansible-playbook playbooks/bootstrap/02-build-iso.yml
```

### 3. Proxmox + Ceph

Run everything from `infrastructure/ansible` so `ansible.cfg`, the inventory,
and roles resolve:

```bash
ansible-playbook site.yml                            # setup + reboot + cluster + Ceph
ansible-playbook playbooks/proxmox/harden.yml        # optional hardening
ansible-playbook playbooks/proxmox/health-check.yml  # verify
```

### 4. Kubernetes (pick one)

**Talos** (immutable, API-driven):

```bash
ansible-playbook playbooks/talos/01-provision-vms.yml
ansible-playbook playbooks/talos/02-cluster-create.yml
ansible-playbook playbooks/talos/health-check.yml
```

**Flatcar** (kubeadm-based):

```bash
ansible-playbook playbooks/flatcar/01-provision-vms.yml
ansible-playbook playbooks/flatcar/02-cluster-bootstrap.yml
```

The two stacks have separate node IPs, pod/service CIDRs and cluster names,
so they coexist. Check RAM before running both — the defaults want 36GB per
stack. To tear one down:

```bash
ansible-playbook playbooks/remove-vms.yml -e "vm_type=talos"
```

## Common Operations

```bash
# Upgrade Talos + Kubernetes to the versions in versions.yaml
ansible-playbook playbooks/talos/upgrade.yml

# Apply Flatcar OS updates with node draining
ansible-playbook playbooks/flatcar/update.yml

# Add a Proxmox node / expand Ceph
ansible-playbook playbooks/proxmox/cluster-add-node.yml
ansible-playbook playbooks/proxmox/ceph-expand.yml

# Add Kubernetes nodes (define in inventory first)
ansible-playbook playbooks/talos/add-node.yml -e "new_nodes=['talos-worker-04']"
```

## Documentation

| Topic | Link |
|-------|------|
| Architecture and design decisions | [docs/architecture/](docs/architecture/) |
| Specs: planned work + implemented subsystems | [docs/specs/](docs/specs/) |
| Bare-metal Proxmox auto-install | [infrastructure/linux/proxmox/](infrastructure/linux/proxmox/) |
| Ansible usage and troubleshooting | [infrastructure/ansible/](infrastructure/ansible/) |
| Proxmox clustering | [CLUSTER.md](infrastructure/ansible/playbooks/proxmox/CLUSTER.md) |
| Ceph storage | [CEPH.md](infrastructure/ansible/playbooks/proxmox/CEPH.md) |
| Proxmox hardening | [HARDENING.md](infrastructure/ansible/playbooks/proxmox/HARDENING.md) |
| Talos lifecycle | [playbooks/talos/](infrastructure/ansible/playbooks/talos/) |
| Flatcar lifecycle | [playbooks/flatcar/](infrastructure/ansible/playbooks/flatcar/) |
| Talos networking | [NETWORK.md](infrastructure/linux/talos/NETWORK.md) |

## Version Management

Component versions live in `infrastructure/linux/{talos,flatcar}/versions.yaml`
and are updated automatically by [Renovate](renovate.json) via
`# renovate:` annotations. Talos patch releases auto-merge after a 3-day
soak; Kubernetes and Flatcar updates always require manual review — a
Kubernetes minor has to wait for a Talos release that targets it.

The Proxmox ISO has no Renovate datasource and is bumped by hand; see the
comment at the top of `infrastructure/linux/proxmox/versions.yaml`.

## Security Notes

- Generated cluster secrets, machine configs, and kubeconfigs are written to
  gitignored `generated/` directories — never commit them.
- SSH host key checking is disabled in `ansible.cfg` as a deliberate homelab
  tradeoff; re-enable it for anything internet-facing.
- A [pre-commit](.pre-commit-config.yaml) config with gitleaks is included:
  `pip install pre-commit && pre-commit install`.

## License

MIT — see [LICENSE](LICENSE).
