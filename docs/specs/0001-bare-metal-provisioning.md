# 0001 — Bare-metal Proxmox provisioning

**Status:** Implemented
**Serves goals:** Learning (Proxmox, Ansible); repo organization
**Implementing files:** `infrastructure/ansible/playbooks/bootstrap/01-render-answers.yml`,
`02-build-iso.yml`, `infrastructure/linux/proxmox/` (template, versions, Dockerfile, README)

## Context

Everything above the hypervisor is automated, but installing Proxmox itself
was a manual ISO walk-through. This spec covers the unattended path: boot a
node from a USB stick and it comes up as a fully installed PVE node ready for
`01-initial-setup.yml`, using Proxmox's official
[Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
with [autopve](https://github.com/natankeddem/autopve) as the answer server
(`https://proxmox-answers.internal.bluespeed.info/`).

## Requirements

- **BMP-01** The prepared ISO MUST be generic: it bakes in only the autopve
  URL (`autoinstall_url`). One image serves every node, present and future.
- **BMP-02** The baked URL MUST be a DNS name, so the answer server can move
  (e.g. onto the cluster) with a DNS repoint and no ISO rebuild.
- **BMP-03** Per-node identity (fqdn, static management IP) MUST be derived
  from `inventory.yaml` + `vars.yml` — the repo is the source of truth even
  though delivery happens through autopve's UI.
- **BMP-04** The installer MUST set everything no playbook configures:
  hostname/FQDN, static management IP/gateway/DNS, timezone, locale, root
  password, and disk layout.
- **BMP-05** The answer MUST inject the operator's GitHub SSH keys
  (`root-ssh-keys`), so first Ansible contact is key-based (no `-k`).
- **BMP-06** Disk layout MUST be ext4 + LVM on `/dev/sda` only, preserving
  `local-lvm` (VMP-05) and leaving all other disks untouched for Ceph
  (CEPH-06).
- **BMP-07** The raw root password MUST never be written to disk; only a
  sha512 hash may appear, and only under gitignored `generated/` paths.
- **BMP-08** The PVE ISO version and sha256 MUST be pinned in
  `infrastructure/linux/proxmox/versions.yaml`, and the download MUST fail
  hard on checksum mismatch.
- **BMP-09** Rendered complete answers MUST pass
  `proxmox-auto-install-assistant validate-answer` before use.

## Interfaces

Consumes: `github_username`, `domain_name`, `timezone`, `dns_servers`,
`mgmt_gateway`, `mgmt_cidr_bits`, `root_mailto`, `pve_country`,
`pve_keyboard`, `autoinstall_url`, optional `autoinstall_cert_fingerprint`.
Requires DHCP on the management LAN (the installer needs a temporary address
to fetch its answer) and autopve reachable at install time.

## Acceptance criteria

- [ ] `01-render-answers.yml` renders `default.toml` + per-node files and the
      built-in `validate-answer` step passes for every node.
- [ ] `02-build-iso.yml` verifies the pinned sha256 and `inspect-iso` shows
      the autopve URL.
- [ ] A test VM (SCSI disk → `sda`, MAC registered in autopve) installs
      unattended and `ansible <host> -m ping` succeeds with no `-k`.
- [ ] A node with an unknown MAC appears in autopve's request log with enough
      information to register it (the new-node onboarding path).

## Known limitations

- autopve configuration is UI-only: rendered answer content is pasted in
  manually; there is no API-driven sync from the repo.
- The answer is served over the LAN to anyone who POSTs matching system info;
  it contains the password hash and public keys. Acceptable on a trusted
  homelab LAN; run the answer server only during install windows.
- Node matching (MAC/serial) lives in autopve, not in the repo.
