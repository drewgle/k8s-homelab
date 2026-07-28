# Proxmox VE Bare-Metal Auto-Install

Turn a blank machine into an Ansible-ready Proxmox VE node with nothing but a
USB stick: boot it, walk away, and ~10 minutes later the node is on its static
management IP with root SSH keys installed. Built on Proxmox's official
[Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
in `partition` fetch mode — the answer file rides on the USB stick itself.

## How It Works

```
USB stick
├── prepared ISO (generic)      ──boot──> installer reads answer.toml from
└── PROXMOX-AIS partition                 the PROXMOX-AIS partition
    └── answer.toml (per-node)                 │
                                    unattended install
                                          │
                                   reboots onto static IP, root SSH keys installed
                                          │
                                   ansible-playbook playbooks/proxmox/01-initial-setup.yml   (no -k!)
```

- The prepared ISO is **generic** — it bakes in nothing node-specific, not
  even a URL. One image serves every node, including future ones.
- Per-node identity (hostname, static IP) lives in the `answer.toml` written
  to the stick's `PROXMOX-AIS` partition, rendered from this repo's
  `inventory.yaml` + `vars.yml` so the repo stays the source of truth.
- Retargeting the stick to another node means rewriting only the small answer
  partition — the ISO is never rebuilt.
- No answer server and no network dependency at install time: the static
  network configuration comes from the answer itself.

## Prerequisites

- The Ansible control node is a Linux machine with **Docker** installed
  (`proxmox-auto-install-assistant` is Debian-only, so it runs in a small
  container) and Python **passlib** for password hashing
  (`pipx inject ansible passlib`, `pip install passlib`, or
  `apt install python3-passlib`, depending on how Ansible is installed).
- `vars.yml` filled in: `github_username`, `domain_name`, `timezone`,
  `dns_servers`, plus the auto-install block (`mgmt_gateway`,
  `mgmt_cidr_bits`, `root_mailto`, `pve_country`, `pve_keyboard`).

## 1. Render and Validate Answer Files

From `infrastructure/ansible`:

```bash
ansible-playbook playbooks/bootstrap/01-render-answers.yml
```

Prompts once for the root password to set on the new nodes (only its sha512
hash is written, and only under the gitignored `generated/` directory). It
renders one complete answer per node into
`infrastructure/linux/proxmox/generated/answers/` (`pve1.toml`, `pve2.toml`,
...), each validated by `proxmox-auto-install-assistant validate-answer`.

## 2. Build the USB Image

```bash
ansible-playbook playbooks/bootstrap/02-build-iso.yml
```

Downloads the Proxmox ISO pinned in [versions.yaml](versions.yaml) (sha256
verified — the download is skipped when the file is already present and
intact), then prepares it with `--fetch-from partition` and prints an
`inspect-iso` summary. Output:
`infrastructure/linux/proxmox/generated/proxmox-ve_<version>-auto.iso`

## 3. Write the USB Stick (manual, destructive)

Double-check the device name — this erases it:

```bash
lsblk                       # identify your USB stick, e.g. /dev/sdX
sudo dd if=infrastructure/linux/proxmox/generated/proxmox-ve_<version>-auto.iso \
  of=/dev/sdX bs=4M conv=fsync status=progress
```

GUI alternatives: USBImager or balenaEtcher. If you use Rufus on Windows,
you **must** choose "DD Image mode" when prompted — the prepared ISO is a
hybrid image and Rufus's default ISO-extraction mode breaks it.

## 4. Write the Answer Partition (per node)

The installer looks for a partition labeled `proxmox-ais` (case-insensitive)
containing `answer.toml` at its root. Append one in the free space after the
ISO image and drop the target node's answer onto it:

```bash
sudo sgdisk -e -n 0:0:+16M -c 0:proxmox-ais /dev/sdX   # append a 16 MB partition
sudo partprobe /dev/sdX
lsblk /dev/sdX                                          # note the new partition, e.g. /dev/sdX3
sudo mkfs.vfat -F 32 -n PROXMOX-AIS /dev/sdX3
sudo mount /dev/sdX3 /mnt
sudo cp infrastructure/linux/proxmox/generated/answers/pve1.toml /mnt/answer.toml
sudo umount /mnt
```

**This is the only step that repeats per node.** Installing pve2 next? Mount
the partition again and replace `answer.toml` with `pve2.toml` — no dd, no
rebuild. Adding future nodes (pve4, pve5, ...) is the same flow: add the host
to `inventory.yaml`, re-run the render playbook, rewrite the answer partition.

> The stick is now node-specific: it installs whichever identity is in
> `answer.toml`, on whatever machine you boot from it. Write the partition
> immediately before each install and double-check which node it targets.

## 5. Boot the Node

Plug in the stick, power on, F12 (M710q) → boot from USB. The install runs
completely unattended and the machine reboots into Proxmox on its static IP.

## 6. Hand Off to Ansible

```bash
ansible pve1 -m ping                                        # key auth, no -k needed
ansible-playbook playbooks/proxmox/01-initial-setup.yml     # then the normal chain / site.yml
```

The installer already planted your GitHub SSH keys for root, so the
password-based `-k` first contact documented for manually-installed nodes is
unnecessary.

## Design Notes

- **ext4 + LVM on /dev/sda**: matches the `local-lvm` storage the VM
  playbooks expect, and leaves every other disk untouched for Ceph
  (`playbooks/proxmox/ceph/03-osd-add.yml` claims all non-sda disks as OSDs).
- **Version pinning**: [versions.yaml](versions.yaml) is hand-bumped (no
  Renovate datasource exists for Proxmox ISOs).
- **Secrets**: rendered answers contain the root password *hash* and public
  SSH keys only, and live exclusively under the gitignored `generated/`.
  Never commit them; the copy on the USB answer partition is unencrypted, so
  wipe or rewrite that partition once installs are done.
