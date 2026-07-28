# Proxmox VE Security Hardening

This playbook implements comprehensive security hardening for Proxmox VE infrastructure, protecting your homelab from common threats and vulnerabilities.

## Overview

The hardening playbook enhances security across multiple layers:

- **SSH Hardening** - Secure remote access configuration
- **Firewall Protection** - Network-level security controls
- **System Hardening** - Kernel and OS-level protections
- **Fail2Ban** - Intrusion prevention system
- **Audit Logging** - Security event monitoring
- **File System Security** - Permission and access controls
- **Proxmox-Specific** - Platform-specific security measures
- **Automatic Updates** - Continuous security patch management

## Prerequisites

### Before Running

- **Initial Setup Complete** - Run `01-initial-setup.yml` first
- **Network Planning** - Document allowed services and ports
- **Backup Configuration** - Create system backups before hardening
- **Test Environment** - Verify changes in non-production first
- **SSH Key Access** - Ensure SSH key authentication works

### Required Variables

Add these to your `vars.yml`:

```yaml
# Optional: Customize SSH port (default: 22)
ssh_port: 22

# Optional: Fail2ban notification email
fail2ban_email: "admin@homelab.local"

# Optional: hosts allowed to manage the cluster (SSH, web UI, consoles,
# live migration). Defaults to the Proxmox cluster network plus every node.
# Getting this wrong locks you out — see "Firewall Configuration" below.
firewall_management_sources:
  - "192.168.1.0/24"
```

## Usage

### Standard Hardening

```bash
# Run complete hardening on all nodes
ansible-playbook playbooks/proxmox/harden.yml

# Run on specific hosts
ansible-playbook playbooks/proxmox/harden.yml --limit node1,node2

# Dry run to see what would change
ansible-playbook playbooks/proxmox/harden.yml --check
```

### Verify Hardening

```bash
# Check security status on all nodes
ansible-playbook playbooks/proxmox/verify-hardening.yml

# Check specific nodes only
ansible-playbook playbooks/proxmox/verify-hardening.yml --limit node1,node2
```

### Custom Configuration

For specific requirements, modify the playbook variables:

```bash
# Create custom vars file
cp vars.yml custom-security.yml

# Edit security settings
vim custom-security.yml

# Run with custom settings
ansible-playbook playbooks/proxmox/harden.yml -e @custom-security.yml
```

## What the Playbook Does

### SSH Security Hardening

**Disabled Features:**

- Password authentication (keys only)
- Root password login
- Empty passwords
- X11 forwarding
- DNS lookups
- Weak ciphers and algorithms

**Enhanced Settings:**

- Limited authentication attempts (3 max)
- Connection timeouts
- Strong cryptographic algorithms
- Protocol 2 only

**Files Modified:**

- `/etc/ssh/sshd_config` - Main SSH configuration
- Automatic backup created before changes

### Firewall Configuration (Proxmox firewall)

The built-in Proxmox firewall is the single managed firewall on these nodes.
It runs on the nftables backend, its configuration lives in the cluster
filesystem so every node sees the same rules, and it is visible and editable
in the web UI. The playbook removes UFW if a previous run installed it, so
the two can never double-filter.

**Managed files:**

| File | Scope | Rendered from |
|------|-------|---------------|
| `/etc/pve/firewall/cluster.fw` | datacenter: master switch, aliases, `management` IPSet | `templates/cluster.fw.j2` |
| `/etc/pve/nodes/<node>/host.fw` | one node's host rules | `templates/host.fw.j2` |

**Default policies:**

- Host incoming: DROP — this is the firewall's behavior whenever it is
  enabled; there is no `policy_in` key in `host.fw`.
- Host outgoing: ACCEPT.
- Guest (VM/CT) traffic: ACCEPT, set at the datacenter level. VM NICs are
  created with `firewall=1`, so per-guest rules can be added later without
  touching the hypervisor ruleset.

**Allowed by Proxmox itself** — no rule needed, and restricted to the
`management` IPSet:

- SSH (22/tcp), web UI (8006/tcp), SPICE proxy (3128/tcp)
- VNC consoles (5900-5999/tcp)
- **Live migration (60000-60050/tcp)** — the UFW configuration this replaced
  omitted these, which silently broke migration between nodes
- Corosync (5405-5412/udp) between cluster members

**Allowed by the rules this playbook writes:**

- Ceph monitors (3300, 6789/tcp) and OSD/MGR/MDS (6800-7300/tcp), from the
  `ceph_public` alias and, when it differs, the `ceph_cluster` alias
- rpcbind (111/tcp+udp) from the `management` IPSet

**Who counts as a management host:** the `management` IPSet is built from
`firewall_management_sources` (defaults to the Proxmox cluster network) plus
every node's `ansible_host`. Set it in `vars.yml` if you administer the
cluster from a different subnet than the nodes live on — **if your
workstation is not in this set you will lose SSH and web UI access.**

```yaml
firewall_management_sources:
  - "192.168.1.0/24"     # management LAN
  - "10.10.0.5"          # jump host
```

### Fail2Ban Intrusion Prevention

**Protected Services:**

- SSH (authentication failures)
- Proxmox Web Interface (login failures)
- System authentication

**Default Settings:**

- Ban Time: 1 hour
- Max Retries: 3 attempts
- Find Time: 10 minutes
- Custom Proxmox filter

**Files Created:**

- `/etc/fail2ban/jail.local` - Main configuration
- `/etc/fail2ban/filter.d/proxmox-web.conf` - Proxmox-specific rules

### System Kernel Hardening

**Network Security:**

- IP forwarding (controlled)
- Source routing disabled
- ICMP redirects blocked
- SYN flood protection
- Reverse path filtering
- Martian packet logging

**Memory Protection:**

- Address space randomization
- Kernel pointer restrictions
- dmesg access restrictions
- Ptrace scope limitations

**File System Security:**

- SUID dump prevention
- Hard/symlink protection
- FIFO protection
- Regular file protection

### Security Services

**Audit System (auditd):**

- Proxmox configuration monitoring
- System call auditing
- File access tracking
- Login/logout monitoring
- Immutable configuration

**Automatic Updates:**

- Security patch automation
- Package list updates
- Automatic cleanup
- Controlled upgrade scheduling

**Time Synchronization:**

- Chrony NTP service
- Servers taken from `ntp_servers` in vars.yml
- Localhost-only access
- Comprehensive logging

### File System Permissions

**Critical Files Protected:**

- `/etc/passwd` (644)
- `/etc/shadow` (640)
- `/etc/ssh/sshd_config` (600)
- `/etc/pve/` (750)

**Security Cleanup:**

- Removed vulnerable packages
- Sticky bits on world-writable directories
- Disabled uncommon network protocols

## Security Verification

### Automated Checks

The verification playbook `verify-hardening.yml` validates:

- **SSH Configuration** - All hardening applied correctly
- **Firewall Status** - Proxmox firewall enabled/running, UFW absent, and
  live migration present in the compiled ruleset
- **Fail2Ban Operation** - Service running with active jails
- **Kernel Parameters** - Security settings applied
- **File Permissions** - Critical files properly protected
- **Service Status** - Security services operational
- **Update Status** - Security patches current

### Manual Verification

```bash
# Check SSH configuration
sshd -T | grep -E "passwordauth|pubkeyauth|permitroot"

# Verify firewall rules
pve-firewall status
pve-firewall compile          # the full ruleset, including Proxmox built-ins

# Check fail2ban status
fail2ban-client status

# Review audit rules
auditctl -l

# Check security updates
apt list --upgradable 2>/dev/null | grep security
```

## Maintenance

### Regular Tasks

**Daily:**

- Monitor fail2ban logs: `tail -f /var/log/fail2ban.log`
- Check security updates: Run verification script

**Weekly:**

- Review audit logs: `ausearch -ts week-ago`
- Verify backup integrity
- Update security rules if needed

**Monthly:**

- Full security assessment
- Update hardening configuration
- Test incident response procedures

### Log Monitoring

**Key Log Locations:**

- Fail2ban: `/var/log/fail2ban.log`
- Audit: `/var/log/audit/audit.log`
- Authentication: `/var/log/auth.log`
- Proxmox: `/var/log/pvedaemon.log`
- Firewall: `/var/log/pve-firewall.log`

## Troubleshooting

### Common Issues

**SSH Access Lost:**

```bash
# From Proxmox console
systemctl status ssh
journalctl -u ssh -n 20

# Reset SSH config (emergency)
cp /etc/ssh/sshd_config.backup /etc/ssh/sshd_config
systemctl restart ssh
```

**Firewall Blocking Services:**

```bash
# Check firewall logs (set log_level_in to "info" in host.fw to populate this)
tail -f /var/log/pve-firewall.log

# Show the ruleset actually in force, built-ins included
pve-firewall compile

# Add a rule permanently: edit templates/host.fw.j2 and re-run harden.yml
```

**Fail2Ban Issues:**

```bash
# Check fail2ban status
fail2ban-client status

# Unban IP address
fail2ban-client set [jail] unbanip [ip]

# Restart service
systemctl restart fail2ban
```

**Performance Impact:**

- Audit system may increase I/O load
- Fail2ban uses minimal resources
- Firewall adds negligible latency
- Monitor with: `htop`, `iotop`, `netstat`

### Recovery Procedures

**Emergency SSH Access:**

1. Use Proxmox VE console (physical/IPMI)
2. Restore SSH config from backup
3. Restart SSH service
4. Re-run hardening with corrections

**Firewall Lockout:**

1. Access via Proxmox console (physical/IPMI)
2. Disable the firewall: `pve-firewall stop`, or set `enable: 0` in
   `/etc/pve/nodes/<node>/host.fw`
3. Fix `firewall_management_sources` in `vars.yml` — a lockout here almost
   always means your workstation is outside the `management` IPSet
4. Re-run `harden.yml`, then `pve-firewall start`

## Advanced Configuration

### Custom Security Rules

Add to playbook variables:

```yaml
# Custom sysctl parameters
custom_sysctl_params:
  - { name: 'net.core.somaxconn', value: '65535' }
  - { name: 'vm.swappiness', value: '10' }

# Enhanced audit rules
custom_audit_rules:
  - "-w /etc/hosts -p wa -k network-config"
  - "-w /etc/resolv.conf -p wa -k network-config"
```

### Integration with Monitoring

**Prometheus Integration:**

Additional host ports are added by editing `templates/host.fw.j2` and
re-running `harden.yml` — the ruleset is a rendered file, not a list of
imperative rules. For a node exporter scraped from the Kubernetes VLAN:

```
IN ACCEPT -source 192.168.100.0/24 -p tcp -dport 9100 -log nolog # node_exporter
```

**Log Aggregation:**

```yaml
# Configure rsyslog forwarding
rsyslog_remote_server: "log.homelab.local"
rsyslog_remote_port: 514
```

## Security Best Practices

### Ongoing Security

1. **Regular Updates**
   - Apply security patches weekly
   - Test updates in staging first
   - Monitor security advisories

2. **Access Control**
   - Use SSH keys exclusively
   - Implement principle of least privilege
   - Regular access reviews

3. **Monitoring**
   - Set up alerting for security events
   - Regular log analysis
   - Automated threat detection

4. **Backup Security**
   - Encrypt backups
   - Secure backup storage
   - Test recovery procedures

### Compliance Considerations

This hardening configuration addresses:

- **CIS Benchmarks** - Industry security standards
- **NIST Framework** - Cybersecurity best practices
- **ISO 27001** - Information security management
- **GDPR Requirements** - Data protection (if applicable)

## Support and Updates

### Documentation Updates

This hardening guide is maintained alongside the Ansible playbooks. Check Git history for recent security improvements.

### Community Contributions

Security hardening is an ongoing process. Contributions for additional security measures are welcome:

1. Test thoroughly in lab environment
2. Document security benefit
3. Maintain backward compatibility
4. Update verification scripts

For questions or issues, refer to the main project documentation or security forums.
