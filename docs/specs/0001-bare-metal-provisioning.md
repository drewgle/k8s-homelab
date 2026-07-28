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
in `partition` fetch mode — the installer reads `answer.toml` from a FAT
partition labeled `proxmox-ais` (matched case-insensitively) on the install
medium itself. No answer server, no network dependency at install time; the
repo is the end-to-end source of truth.

## Requirements

- **BMP-01** The prepared ISO MUST be generic: it is prepared with
  `--fetch-from partition` and bakes in nothing node-specific — not even a
  URL. One image serves every node, present and future.
- **BMP-02** The answer MUST be read from a partition labeled `proxmox-ais`
  on the install USB, appended after the ISO image. The stick carries exactly
  one node's complete answer at a time; retargeting the stick to another node
  means rewriting only that partition, never the ISO.
- **BMP-03** Per-node identity (fqdn, static management IP) MUST be rendered
  from `inventory.yaml` + `vars.yml` into the node's complete answer file,
  with no manual transfer step between the repo and the installer.
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
- **BMP-09** Rendered answers MUST pass
  `proxmox-auto-install-assistant validate-answer` before use.

## Interfaces

Consumes: `github_username`, `domain_name`, `timezone`, `dns_servers`,
`mgmt_gateway`, `mgmt_cidr_bits`, `root_mailto`, `pve_country`,
`pve_keyboard`. Requires nothing from the network at install time: the
answer is on the stick and the static network configuration comes from the
answer itself.

## Acceptance criteria

- [ ] `01-render-answers.yml` renders one complete answer per node and the
      built-in `validate-answer` step passes for every node.
- [ ] `02-build-iso.yml` verifies the pinned sha256 and `inspect-iso` shows
      partition fetch mode.
- [ ] A test VM (SCSI disk → `sda`, plus a small extra disk labeled
      `proxmox-ais` carrying one node's `answer.toml`) installs unattended
      and `ansible <host> -m ping` succeeds with no `-k`.
- [ ] New-node onboarding: add the host to `inventory.yaml`, re-run the
      render playbook, rewrite the answer partition, boot. No ISO rebuild.

## Known limitations

- The stick is node-specific at write time: booting the wrong machine from it
  installs the wrong identity. Mitigated by the one-stick-at-a-time workflow
  (write the answer partition immediately before each install).
- The answer sits unencrypted on the USB partition and contains the root
  password hash and public SSH keys; wipe or rewrite the partition once
  installs are done.
- There is no central request log of unknown nodes (the old answer-server
  onboarding path). Node identity is chosen by which answer is written to the
  stick, so MAC/serial matching no longer exists anywhere.
