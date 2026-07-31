# GitOps Homelab: From Blank Hardware to a Self-Healing Kubernetes Platform

Cloud bills keep climbing and every breach headline is a reminder of how
little of your own data you actually hold. A homelab is the obvious answer —
right up until you have hand-configured three machines, forgotten what you
did to the second one, and can't rebuild any of them.

This talk is about the other approach: an entire homelab defined in one git
repository. We start at blank hardware and an unattended-install USB stick,
build a Proxmox cluster with Ceph storage, bring up Kubernetes on Talos
Linux — an immutable OS with no shell, no SSH and no package manager, managed
entirely through an API — and hand the cluster over to Flux, which reconciles
everything above it straight from the repo.

Then we delete it all and watch it come back.

You'll see the tools (Ansible, Proxmox, Ceph, Talos, Flux, Renovate), the
tradeoffs behind each choice, and the parts that are genuinely annoying. No
homelab background needed, and everything demonstrated is in a public repo
you can clone and run against your own hardware.
