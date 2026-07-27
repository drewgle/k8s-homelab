# Proxmox VE Bare-Metal Auto-Install

Turn a blank machine into an Ansible-ready Proxmox VE node with nothing but a
USB stick: boot it, walk away, and ~10 minutes later the node is on its static
management IP with root SSH keys installed. Built on Proxmox's official
[Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)
plus [autopve](https://github.com/natankeddem/autopve) as the answer server.

## How It Works

```
USB (prepared ISO) ──boot──> installer DHCPs, POSTs system info ──> autopve
                                                                      │ matches node by MAC/serial
                             unattended install <── answer.toml ──────┘
                                    │
                             reboots onto static IP, root SSH keys installed
                                    │
                             ansible-playbook playbooks/proxmox/01-initial-setup.yml   (no -k!)
```

- The prepared ISO is **generic** — it only bakes in the autopve URL
  (`autoinstall_url` in `vars.yml`). One stick serves every node, including
  future ones.
- Because the URL is a DNS name, moving autopve later (e.g. onto the cluster
  itself) is just a DNS repoint — the USB keeps working unchanged.
- Per-node identity (hostname, static IP) lives in autopve answers, whose
  content is rendered from this repo's `inventory.yaml` + `vars.yml` so the
  repo stays the source of truth.

## Prerequisites

- The Ansible control node is a Linux machine with **Docker** installed
  (`proxmox-auto-install-assistant` is Debian-only, so it runs in a small
  container) and Python **passlib** for password hashing
  (`pipx inject ansible passlib`, `pip install passlib`, or
  `apt install python3-passlib`, depending on how Ansible is installed).
- autopve reachable (default: `https://proxmox-answers.internal.bluespeed.info/`).
- DHCP available on the management LAN — the installer needs a temporary
  address to fetch its answer before it configures the static one.
- `vars.yml` filled in: `github_username`, `domain_name`, `timezone`,
  `dns_servers`, plus the auto-install block (`mgmt_gateway`,
  `mgmt_cidr_bits`, `root_mailto`, `pve_country`, `pve_keyboard`,
  `autoinstall_url`, optional `autoinstall_cert_fingerprint` — only needed
  when the autopve TLS certificate is not publicly trusted).

## 1. Render and Validate Answer Files

From `infrastructure/ansible`:

```bash
ansible-playbook playbooks/bootstrap/01-render-answers.yml
```

Prompts once for the root password to set on the new nodes (only its sha512
hash is written, and only under the gitignored `generated/` directory). It
renders into `infrastructure/linux/proxmox/generated/answers/`:

| File | Purpose |
|------|---------|
| `default.toml` | Shared settings — paste into autopve's **Default** answer |
| `<node>.toml` (e.g. `pve1.toml`) | Per-node overrides (fqdn + network) — paste into that node's autopve answer |
| `<node>-full.toml` | Complete merged answer, validated by `proxmox-auto-install-assistant validate-answer` (autopve never sees these) |

## 2. Configure autopve

1. Open autopve and paste `default.toml` into the **Default** answer.
2. Create an answer named for each node (`pve1`, `pve2`, `pve3`) containing
   that node's `<node>.toml` content. autopve inherits everything else from
   Default.
3. Give each answer a match rule on the node's MAC address or DMI serial.

**Don't know a node's MAC/serial?** Boot it from the USB once — autopve logs
every incoming request with the full system information the installer POSTs.
Copy the identifier into a new answer and boot the node again. This is also
the workflow for adding future nodes (pve4, pve5, ...): add the host to
`inventory.yaml`, re-run the render playbook, create the autopve answer, boot.

## 3. Build the USB Image

```bash
ansible-playbook playbooks/bootstrap/02-build-iso.yml
```

Downloads the Proxmox ISO pinned in [versions.yaml](versions.yaml) (sha256
verified — the download is skipped when the file is already present and
intact), then bakes in the autopve URL with `prepare-iso` and prints an
`inspect-iso` summary. Output:
`infrastructure/linux/proxmox/generated/proxmox-ve_<version>-auto.iso`

## 4. Write the USB Stick (manual, destructive)

Double-check the device name — this erases it:

```bash
lsblk                       # identify your USB stick, e.g. /dev/sdX
sudo dd if=infrastructure/linux/proxmox/generated/proxmox-ve_<version>-auto.iso \
  of=/dev/sdX bs=4M conv=fsync status=progress
```

GUI alternatives: USBImager or balenaEtcher. If you use Rufus on Windows,
you **must** choose "DD Image mode" when prompted — the prepared ISO is a
hybrid image and Rufus's default ISO-extraction mode breaks it.

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
  Never commit them; treat autopve's answer store with the same care.
- **Future**: once the Kubernetes cluster is up, run a copy of autopve on it
  (under `applications/`), migrate the answers, and repoint the
  `proxmox-answers` DNS record. No ISO rebuild required.
