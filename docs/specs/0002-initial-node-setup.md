# 0002 — Initial node setup

**Serves goals:** Learning (Proxmox, Ansible); repo organization
**Planned files:** `infrastructure/ansible/playbooks/proxmox/01-initial-setup.yml`,
`02-reboot.yml`

## Context

First-contact configuration that turns a freshly installed PVE node (manual
or via spec [0001](0001-bare-metal-provisioning.md)) into a patched,
key-accessible node with community repositories. It runs before everything
else in `site.yml`.

## Requirements

- **INIT-01** Root SSH access MUST be key-based after the first run: all
  public keys from `https://github.com/{{ github_username }}.keys` (GitHub's
  [public-key endpoint](https://docs.github.com/en/rest/users/keys), filtered
  to `ssh-rsa`/`ssh-ed25519`/`ecdsa-*`) are installed for root. Manual
  installs use `-k` for the first run only; auto-installed nodes (BMP-05)
  never need it.
- **INIT-02** Repository configuration MUST be release-agnostic: the
  [`pve-no-subscription`](https://pve.proxmox.com/wiki/Package_Repositories)
  suite is derived from the node's detected Debian codename
  (`ansible_distribution_release`), never hardcoded.
- **INIT-03** All enterprise repositories MUST be disabled, in both formats:
  one-line `.list` entries (PVE 7/8) are commented out and
  [deb822](https://manpages.debian.org/stable/apt/sources.list.5.en.html)
  `.sources` stanzas (PVE 9+) get `Enabled: false`. Discovery is by content
  match on `enterprise.proxmox.com`, so the Ceph enterprise repo is covered
  too.
- **INIT-04** The playbook MUST own `pve-no-subscription.list` outright
  (full-file write), so stale suite lines from earlier runs self-repair.
- **INIT-05** The subscription-nag dialog MUST be disabled by rewriting the
  `.data.status.toLowerCase() !== 'active'` check in `proxmoxlib.js`, and the
  patch MUST survive `proxmox-widget-toolkit` upgrades via a
  [`DPkg::Post-Invoke`](https://manpages.debian.org/stable/apt/apt.conf.5.en.html)
  hook (`/etc/apt/apt.conf.d/no-nag-script`).
- **INIT-06** If the nag pattern is not found (widget-toolkit changed shape),
  the run MUST surface a visible warning rather than fail or stay silent.
- **INIT-07** The node MUST end fully dist-upgraded with the baseline package
  set (`vim htop curl wget git nfs-common open-iscsi`) installed.
- **INIT-08** The playbook itself MUST NOT reboot. Pending reboots are
  reported, and `02-reboot.yml` performs them serially (one node at a time),
  verifying `pvedaemon`/`pveproxy`/`pvestatd` return afterwards.
- **INIT-09** `pveproxy` MUST be restarted when the nag patch changes so the
  UI serves the patched library immediately.

## Interfaces

Consumes: `github_username` (required). Inventory: `ansible_user: root` for
all `proxmox` hosts.

## Acceptance criteria

- [ ] `ansible pveN -m ping` succeeds without `-k` after the first run.
- [ ] `apt-get update` reports no enterprise-repo errors and pulls from
      `download.proxmox.com/debian/pve <codename> pve-no-subscription`.
- [ ] `grep -c NoMoreNagging /usr/share/javascript/proxmox-widget-toolkit/proxmoxlib.js`
      ≥ 1, and the web UI shows no subscription dialog after a hard refresh.
- [ ] After `apt upgrade` replaces proxmox-widget-toolkit, the dialog is
      still absent (apt hook re-applied the patch).
- [ ] Re-running the playbook reports no changes (idempotent).

## Known limitations

- The nag patch depends on a specific source string in proxmoxlib.js; a
  future widget-toolkit rewrite would surface INIT-06's warning and need a
  patch update here and in the apt hook.
- Everything runs as root over SSH; there is no non-root automation user
  (accepted for this homelab; revisit if the trust model changes).
