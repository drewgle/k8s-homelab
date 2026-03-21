#!/bin/bash

# Quick setup script for Proxmox Homelab Ansible

set -e

echo "🏠 Proxmox Homelab Setup"
echo "======================="

# Check if vars.yml exists
if [[ ! -f "vars.yml" ]]; then
    echo "📋 Creating vars.yml from example..."
    cp vars.yml.example vars.yml
    echo "✅ Created vars.yml - please edit it with your configuration"
    echo ""
    echo "Required changes:"
    echo "  1. Set your github_username in vars.yml"
    echo "  2. Update IP addresses in inventory.yaml"
    echo ""
    read -p "Press Enter to open vars.yml for editing..." 
    ${EDITOR:-nano} vars.yml
else
    echo "✅ vars.yml already exists"
fi

# Check if inventory has been customized
if grep -q "192.168.1.10" inventory.yaml; then
    echo "📝 inventory.yaml still has example IPs"
    echo ""
    read -p "Press Enter to open inventory.yaml for editing..." 
    ${EDITOR:-nano} inventory.yaml
else
    echo "✅ inventory.yaml appears to be customized"
fi

echo ""
echo "🚀 Ready to run!"
echo ""
echo "Next steps:"
echo "  1. ansible-playbook -k playbooks/proxmox/initial-setup.yml"
echo "  2. ansible-playbook playbooks/proxmox/reboot.yml (if needed)"
echo "  3. ansible-playbook playbooks/proxmox/health-check.yml (health check)"
echo ""
echo "Use 'ansible-playbook --check' for dry run mode"