# 0005 — Node security hardening

**Status:** Accepted
**Serves goals:** Learning (Proxmox, security); repo organization
**Planned files:** `infrastructure/ansible/playbooks/proxmox/harden.yml`,
`verify-hardening.yml`, `infrastructure/ansible/templates/jail.local.j2`,
`cluster.fw.j2`, `host.fw.j2`

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
- **HARD-03** The
  [built-in Proxmox firewall](https://pve.proxmox.com/pve-docs/chapter-pve-firewall.html)
  is the *single* managed firewall, and UFW MUST be absent so the two can
  never double-filter. It is the platform's supported path: nftables backend,
  configuration replicated through pmxcfs, and visible in the web UI.
  - Host input policy is DROP (the firewall's behavior whenever enabled);
    output is ACCEPT.
  - Guest policy stays ACCEPT at the datacenter level, so the `firewall=1`
    flag on VM NICs (spec [0006](0006-vm-platform.md)) becomes a live hook
    for per-guest rules rather than an inert setting.
  - Proxmox's own management rules cover 22/tcp (SSH), 8006/tcp (web UI),
    3128/tcp (SPICE proxy), 5900-5999/tcp (VNC), 5405-5412/udp (corosync)
    and **60000-60050/tcp (live migration)** — the last of which a
    hand-maintained UFW allowlist is easy to omit, silently breaking
    migration between nodes.
  - Only Ceph (3300, 6789, 6800-7300/tcp — see the
    [Ceph network config reference](https://docs.ceph.com/en/latest/rados/configuration/network-config-ref/))
    and rpcbind (111/tcp+udp) need explicit rules, sourced from the Ceph
    networks and the management IPSet respectively.
- **HARD-03a** The `management` IPSet MUST be rendered from
  `firewall_management_sources` (default: the Proxmox cluster network) plus
  every inventory node's address. This is the lockout-critical value: a host
  outside the set cannot reach SSH or the web UI.
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
- [ ] `pve-firewall status` reports `enabled/running` on every node, and
      `ufw` is not installed.
- [ ] `pve-firewall compile` shows the migration range 60000-60050 and the
      Ceph rules, and a live migration between two nodes succeeds with the
      firewall on.
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
- Guest traffic is unfiltered (HARD-03). The `firewall=1` flag on VM NICs
  (spec [0006](0006-vm-platform.md)) makes per-guest rules possible, but none
  are specified here — Kubernetes node policy belongs to the cluster layer.
- `firewall_management_sources` is the one setting that can lock the operator
  out of every node at once. Console access is the recovery path
  (see HARDENING.md).
