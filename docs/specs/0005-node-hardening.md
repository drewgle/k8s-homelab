# 0005 — Node security hardening

**Status:** Implemented
**Serves goals:** Learning (Proxmox, security); repo organization
**Implementing files:** `infrastructure/ansible/playbooks/proxmox/harden.yml`,
`verify-hardening.yml`, `infrastructure/ansible/templates/jail.local.j2`

## Context

Optional but expected hardening pass over the PVE nodes: SSH lockdown,
default-deny firewall, fail2ban, kernel/sysctl hardening, auditing, and
secure time sync. Documented in detail in
[HARDENING.md](../../infrastructure/ansible/playbooks/proxmox/HARDENING.md);
this spec records the invariants.

## Requirements

- **HARD-01** Ordering invariant: `harden.yml` MUST only run after SSH keys
  exist for root (INIT-01 / BMP-05) — it disables password authentication
  (`PasswordAuthentication no`, `PermitRootLogin prohibit-password`) and
  would otherwise lock the operator out.
- **HARD-02** SSH accepts only root (`AllowUsers root`), public-key auth,
  protocol 2, modern KEX/cipher/MAC algorithms only, with bounded auth
  attempts and session keepalives.
- **HARD-03** UFW default policy is deny incoming / allow outgoing / deny
  routed, with an explicit allowlist: 22/tcp (SSH), 8006/tcp (web UI),
  3128/tcp (spice proxy), 5900-5999/tcp (VNC), 5404-5405/udp (corosync),
  111/tcp+udp (rpcbind) — per the
  [Proxmox port list](https://pve.proxmox.com/wiki/Ports). Ceph ports
  (3300, 6789, 6800-7300/tcp — see the
  [Ceph network config reference](https://docs.ceph.com/en/latest/rados/configuration/network-config-ref/))
  are allowed only from `ceph_public_network`. UFW is the *single* managed
  firewall:
  the built-in Proxmox firewall is explicitly kept disabled datacenter-wide
  (`/etc/pve/firewall/cluster.fw`, `enable: 0`) so the two never
  double-filter.
- **HARD-04** [fail2ban](https://github.com/fail2ban/fail2ban) jails cover
  sshd and the Proxmox web UI (custom
  `proxmox-web` filter on pvedaemon auth failures): 3 retries → 1h ban.
- **HARD-05** Kernel hardening sysctls are applied via
  `/etc/sysctl.d/99-security.conf` (rp_filter, no redirects/source routes,
  syncookies, ASLR, restricted dmesg/kptr/ptrace, protected
  links/fifos/regular — largely the
  [KSPP recommended settings](https://kspp.github.io/Recommended_Settings)).
  `net.ipv4.ip_forward=1` MUST stay enabled — Proxmox
  networking depends on it.
- **HARD-06** Rare network protocols (dccp, sctp, rds, tipc, ...) are
  blacklisted from module loading.
- **HARD-07** auditd watches PVE config, SSH config, account files, time
  changes, and sessions; the ruleset is immutable
  ([`-e 2`](https://man7.org/linux/man-pages/man8/auditctl.8.html)), so
  audit-rule changes REQUIRE a reboot to take effect.
- **HARD-08** [Unattended security upgrades](https://wiki.debian.org/UnattendedUpgrades)
  are enabled (`APT::Periodic::Unattended-Upgrade "1"` + distro-security
  origin).
- **HARD-09** Time sync uses [chrony](https://chrony-project.org/) with the
  pools from the `ntp_servers` var; serving time to other hosts is disabled
  (allow 127.0.0.1, deny all).
- **HARD-10** Legacy/insecure packages (telnet, rsh, nis, ntpdate) are
  removed.

## Acceptance criteria

- [ ] `verify-hardening.yml` passes on every node.
- [ ] `ssh -o PreferredAuthentications=password root@node` is refused;
      key-based login still works.
- [ ] `ufw status verbose` shows default deny incoming and exactly the
      allowlisted ports.
- [ ] `fail2ban-client status sshd` and `... status proxmox-web` show both
      jails active.
- [ ] Cluster and Ceph operations still work post-hardening (CLU-04
      acceptance, CEPH acceptance) — the allowlist must not break them.
- [ ] The Proxmox web UI and VM consoles remain reachable.

## Known limitations

- Unattended upgrades of PVE packages can restart services outside
  maintenance windows; acceptable for a homelab.
- auditd immutability (HARD-07) means iterating on audit rules is
  reboot-gated by design.
- The `firewall=1` flag on VM NICs (spec [0006](0006-vm-platform.md)) is
  inert while the PVE firewall is disabled per HARD-03; that is intentional.
