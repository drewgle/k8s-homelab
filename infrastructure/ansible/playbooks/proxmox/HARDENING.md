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

# Optional: Custom firewall rules
custom_firewall_ports:
  - { port: 9090, protocol: tcp, comment: 'Custom Service' }
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

### Firewall Configuration (UFW)

**Default Policies:**

- Incoming: DENY (block all by default)
- Outgoing: ALLOW (permit internal services)
- Forwarding: DENY (restrict routing)

**Allowed Services:**

- SSH (22/tcp)
- Proxmox Web UI (8006/tcp)
- VNC Consoles (5900-5999/tcp)
- Corosync Cluster (5404-5405/udp)
- Ceph Services (if configured)

**Dynamic Rules:**

- Cluster networks automatically allowed
- Source-based restrictions for storage traffic

**Relationship to the Proxmox firewall:** UFW is the single managed firewall
on these nodes. The playbook explicitly keeps the built-in Proxmox firewall
disabled datacenter-wide (`/etc/pve/firewall/cluster.fw` with `enable: 0`) so
the two never double-filter. Do not enable the PVE firewall in the web UI
without removing UFW first.

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
- **Firewall Status** - UFW active with proper rules
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
ufw status verbose

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
- Firewall: `/var/log/ufw.log`

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
# Check UFW logs
tail -f /var/log/ufw.log

# Temporarily allow service
ufw allow [port]/[protocol]

# Check current rules
ufw status numbered
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

1. Access via Proxmox console
2. Disable UFW: `ufw --force disable`
3. Fix configuration
4. Re-enable: `ufw --force enable`

## Advanced Configuration

### Custom Security Rules

Add to playbook variables:

```yaml
# Custom sysctl parameters
custom_sysctl_params:
  - { name: 'net.core.somaxconn', value: '65535' }
  - { name: 'vm.swappiness', value: '10' }

# Additional firewall rules
custom_firewall_rules:
  - { port: 9100, protocol: tcp, comment: 'Prometheus Node Exporter' }
  - { port: 3000, protocol: tcp, comment: 'Grafana Dashboard' }

# Enhanced audit rules
custom_audit_rules:
  - "-w /etc/hosts -p wa -k network-config"
  - "-w /etc/resolv.conf -p wa -k network-config"
```

### Integration with Monitoring

**Prometheus Integration:**

```yaml
# Add to firewall rules
- { port: 9100, protocol: tcp, comment: 'Node Exporter' }

# Install node_exporter after hardening
ansible-playbook monitoring/node-exporter.yml
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
