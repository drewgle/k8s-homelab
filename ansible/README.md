# Proxmox Homelab Ansible Setup

This directory contains Ansible playbooks for setting up and managing a Proxmox VE homelab with 3 servers.

**Organized Structure**: Playbooks are organized by system type in subfolders for better scalability and maintainability.

## Prerequisites

1. Ansible installed on your control machine
2. SSH access to your Proxmox hosts (initially with password, will be replaced with key-based auth)
3. Root access on Proxmox hosts

## Initial Configuration

### 1. Update Inventory

Edit `inventory.yaml` and update the IP addresses for your Proxmox hosts:

```yaml
pve1:
  ansible_host: YOUR_PVE1_IP
pve2:
  ansible_host: YOUR_PVE2_IP
pve3:
  ansible_host: YOUR_PVE3_IP
```

### 2. Configure Variables

Copy the example configuration file and customize it for your environment:

```bash
cp vars.yml.example vars.yml
```

Edit `vars.yml` and set your GitHub username:

```yaml
github_username: "your-github-username"
```

**Note**: The `vars.yml` file is git-ignored to keep your environment-specific settings private.

### 3. Quick Setup (Optional)

For a guided setup experience, run the setup script:

```bash
cd ansible
./setup.sh
```

This script will:
- Create `vars.yml` from the example if it doesn't exist
- Open files for editing if they need customization
- Guide you through the initial configuration

### 3. SSH Key Management

The playbook fetches SSH public keys from a specified GitHub user. The username is configured in the `vars.yml` file you created above.

This will fetch all public SSH keys from `https://github.com/{username}.keys` and add them to the root user's authorized_keys on all Proxmox hosts.

**Alternative: Use local SSH key**

If you prefer to use a local SSH key instead, add this to your `vars.yml`:

```yaml
use_local_ssh_key: true
local_ssh_key_path: "{{ lookup('env','HOME') }}/.ssh/id_rsa.pub"
```

And modify the playbook accordingly to use the local key when `use_local_ssh_key` is true.

## Files Structure

### Configuration Files
- **[inventory.yaml](inventory.yaml)** - Defines your Proxmox hosts and connection details
- **[vars.yml.example](vars.yml.example)** - Example configuration file (copy to vars.yml)
- **vars.yml** - Your actual configuration (git-ignored, create from example)
- **[ansible.cfg](ansible.cfg)** - Ansible configuration settings
- **[.gitignore](.gitignore)** - Keeps sensitive config files out of git
- **[setup.sh](setup.sh)** - Quick setup script for initial configuration

### Playbooks
- **[playbooks/proxmox/](playbooks/proxmox/)** - Proxmox VE specific playbooks
  - **[initial-setup.yml](playbooks/proxmox/initial-setup.yml)** - Complete initial setup
  - **[reboot.yml](playbooks/proxmox/reboot.yml)** - Safe rolling reboots
  - **[health-check.yml](playbooks/proxmox/health-check.yml)** - System health monitoring
- **[site.yml](site.yml)** - Master playbook that runs setup tasks in order

## Playbook Details

#### proxmox/initial-setup.yml

Performs initial setup on all Proxmox hosts:
- ✅ Copies SSH keys from specified GitHub user for passwordless authentication
- ✅ Disables enterprise repositories
- ✅ Enables community repositories  
- ✅ Disables enterprise subscription nags
- ✅ Performs system upgrade (dist-upgrade)
- ✅ Installs useful packages (vim, htop, curl, etc.)
- ✅ Checks for reboot requirements

**Benefits of using GitHub SSH keys:**
- Consistent access across team members
- Centralized key management
- Automatic inclusion of all your GitHub SSH keys
- No need to manage local key files

#### proxmox/reboot.yml

Safely reboots Proxmox hosts one at a time if required after upgrades.

#### proxmox/health-check.yml

Ongoing monitoring and health checks for Proxmox hosts.

## Usage

### First Run (with password authentication)

```bash
cd ansible
ansible-playbook -k playbooks/proxmox/initial-setup.yml
```

The `-k` flag will prompt for the SSH password for the initial connection.

**Note**: Make sure you've created and configured your `vars.yml` file before running the playbook.

### Subsequent Runs (with key authentication)

```bash
ansible-playbook playbooks/proxmox/initial-setup.yml
```

### Reboot if Required

After the initial setup, check if any hosts need rebooting:

```bash
ansible-playbook playbooks/proxmox/reboot.yml
```

### Health Check

Monitor your Proxmox cluster health:

```bash
ansible-playbook playbooks/proxmox/health-check.yml
```

### Dry Run (Check Mode)

To see what changes would be made without actually applying them:

```bash
ansible-playbook --check playbooks/proxmox/initial-setup.yml
```

## Verification

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