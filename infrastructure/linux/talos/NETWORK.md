# Talos Network Configuration Guide

This document explains the network setup for Talos Linux VMs on Proxmox infrastructure.

## Network Architecture

```
┌──────────────────────────────────────────────────────┐
│                    Physical Network                   │
│                   192.168.1.0/24                     │
└──────────────────┬───────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│              Proxmox Cluster Nodes                   │
│         (Management & Ceph Networks)                 │
└──────────────────┬───────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│                  VLAN Bridge                         │
│                   vmbr1.100                          │
└──────────────────┬───────────────────────────────────┘
                   │
┌──────────────────────────────────────────────────────┐
│               Talos VLAN Network                     │
│                192.168.100.0/24                      │
│                                                      │
│  Control Plane Nodes:    Worker Nodes:              │
│  • 192.168.100.201      • 192.168.100.211           │
│  • 192.168.100.202      • 192.168.100.212           │
│  • 192.168.100.203      • 192.168.100.213           │
│                                                      │
│  Gateway: 192.168.100.1                             │
│  DNS: 1.1.1.1, 8.8.8.8                             │
└──────────────────────────────────────────────────────┘
```

## VLAN Configuration

### Network Isolation
- **VLAN ID**: 100 (configurable via `vm_vlan_id`)
- **Subnet**: 192.168.100.0/24 (isolated from management network)
- **Purpose**: Dedicated network for Kubernetes cluster traffic

### Benefits of VLAN Isolation
1. **Security**: Isolates Kubernetes traffic from management interfaces
2. **Traffic Management**: Dedicated bandwidth for cluster communications  
3. **Flexibility**: Easy to apply firewall rules and QoS policies
4. **Scalability**: Can add additional VLANs for different environments

## Static IP Assignment

### Control Plane Nodes
- `talos-cp-01`: 192.168.100.201 (VM ID: 201)
- `talos-cp-02`: 192.168.100.202 (VM ID: 202) 
- `talos-cp-03`: 192.168.100.203 (VM ID: 203)

### Worker Nodes
- `talos-worker-01`: 192.168.100.211 (VM ID: 211)
- `talos-worker-02`: 192.168.100.212 (VM ID: 212)
- `talos-worker-03`: 192.168.100.213 (VM ID: 213)

### IP Range Planning

The authoritative allocation is spec 0006, VMP-12:

- **Gateway**: .1 (192.168.100.1)
- **Control-plane VIP**: .200 (`talos_vip`, etcd-elected)
- **Control Plane**: .201-.210 (supports up to 10 CP nodes)
- **Workers**: .211-.239 (supports up to 29 worker nodes)
- **MetalLB pool**: .240-.250 (spec 0009; .240 shared Gateway, .241 Forgejo SSH)
- **Reserved**: .251-.254 (MetalLB pool growth only)

## Proxmox Bridge Configuration

### Primary Bridge (vmbr0)
- **Purpose**: Management and storage traffic
- **Network**: 192.168.1.0/24
- **Usage**: Proxmox management, Ceph cluster network

### Talos Bridge (vmbr1)
- **Purpose**: Talos/Kubernetes traffic  
- **VLAN Aware**: Yes
- **Tagged VLANs**: 100
- **Bridge Ports**: None (software bridge)

### Bridge Creation
The `01-provision-vms.yml` playbook automatically creates vmbr1 if it doesn't exist:

```bash
# Manual bridge creation (if needed)
ip link add name vmbr1 type bridge
ip link set vmbr1 up

# Add to /etc/network/interfaces
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    bridge-vlan-aware yes
```

## Firewall Considerations

### Talos Required Ports
- **50000/tcp**: Talos API (machine configuration)
- **6443/tcp**: Kubernetes API Server  
- **2379-2380/tcp**: etcd (control plane only)
- **10250/tcp**: Kubelet API
- **10259/tcp**: kube-scheduler
- **10257/tcp**: kube-controller-manager

### Network Policies
Consider implementing firewall rules to:
- Allow Talos cluster internal communication
- Restrict external access to Kubernetes API
- Block cross-VLAN traffic if desired
- Allow DNS and NTP traffic

## Customization

### Alternative Network Ranges
To use different IP ranges, update these variables:

```yaml
# vars.yml
vm_vlan_id: 200                       # Different VLAN
vm_gateway: "10.100.0.1"              # Different gateway
vm_subnet: "10.100.0.0/24"            # VM network CIDR
vm_cidr_bits: "24"                    # Network mask

# inventory.yaml  
talos-cp-01:
  ansible_host: 10.100.0.201          # New IP range
```

### Multiple Environments  
You can create separate VLANs for different environments:

- **Development**: VLAN 100 (192.168.100.0/24)
- **Staging**: VLAN 200 (192.168.200.0/24)  
- **Production**: VLAN 300 (192.168.300.0/24)

## Troubleshooting

### Common Network Issues

**VMs can't reach gateway**
- Verify VLAN configuration on bridge
- Check Proxmox firewall rules
- Ensure gateway is correctly configured

**Talos API not accessible**
- Verify port 50000 is not blocked
- Check VM networking in Proxmox GUI
- Ensure VMs have booted successfully

**DNS resolution fails**
- Verify DNS servers in vars.yml
- Check if firewall blocks DNS traffic
- Ensure network gateway allows external access

### Verification Commands

```bash
# Check bridge existence
ip link show vmbr1

# Verify VLAN configuration  
bridge vlan show dev vmbr1

# Test connectivity to Talos nodes
curl -k https://192.168.100.201:50000/v1/service/list

# Check VM network configuration in Proxmox
qm config 201 | grep net0
```

## Security Best Practices

1. **Isolate Networks**: Keep Talos VLAN separate from management
2. **Firewall Rules**: Implement least-privilege access
3. **Regular Updates**: Use GitOps for automated patching
4. **Monitor Traffic**: Set up network monitoring for the VLAN
5. **Backup Configs**: Version control all network configurations