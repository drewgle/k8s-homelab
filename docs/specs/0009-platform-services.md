# 0009 — Core platform services

**Status:** Draft
**Serves goals:** Fully GitOps-backed deployment; learning k8s; TLS/exposure
(goal 6: Let's Encrypt for private services)
**Depends on:** [0007 GitOps bootstrap](0007-gitops-bootstrap.md); monitoring
storage depends on [0008](0008-kubernetes-storage.md)

## Context

The architecture doc names the target service stack (NGINX ingress,
cert-manager, Prometheus + Grafana, Loki) but the cluster has no
load-balancer implementation, no ingress, no TLS, and no observability. This
spec defines the minimum platform layer that end-user applications (and the
Argo CD UI itself) build on. Everything here deploys through the GitOps tree
from spec 0007 under `applications/system/`.

## Goals

- Services get stable LoadBalancer IPs on the VM VLAN without a cloud
  provider.
- HTTPS ingress for everything with real, publicly trusted Let's Encrypt
  certificates (goal 6), Argo CD first — no browser warnings, no CA imports
  on client machines.
- Metrics, dashboards, and logs for the cluster and its workloads.
- Each component is a self-contained directory a newcomer can read in
  isolation (organization goal).

## Non-goals

- External/public exposure of any service — everything in this spec is
  private (LAN-only). Public exposure goes through Cloudflare per goal 6 and
  is specified in [0012](0012-public-exposure-cloudflare.md). Nothing here
  opens an inbound port on the router.
- Alerting routes (PagerDuty/Slack) — Alertmanager ships with the stack but
  routing stays default until there's an audience for alerts.
- Service mesh, network policies, pod security standards — future specs if a
  need or learning interest materializes.

## Design

Sync-wave ordered components under `applications/system/`:

### MetalLB (wave 1)

- [L2 mode](https://metallb.io/concepts/layer2/) on the VM VLAN. Address
  pool carved from `vm_subnet` outside the
  node range, e.g. `192.168.100.240–192.168.100.250`, defined next to the
  other network values in `vars.yml.example` and mirrored in the manifest
  (single source documented as the manifest; vars.yml comment points to it).

### ingress-nginx (wave 2)

- Single [ingress-nginx](https://kubernetes.github.io/ingress-nginx/)
  controller, `LoadBalancer` service taking the first MetalLB IP.
- Default ingress class `nginx`.

### Domain prerequisite

Goal 6 requires publicly trusted certificates, which requires a real
registered domain — `.local` names cannot get Let's Encrypt certs. The
domain's DNS is hosted on Cloudflare (also a prerequisite for
[0012](0012-public-exposure-cloudflare.md)). Private services live under a
dedicated subdomain, e.g. `*.internal.<domain>`; the `domain_name` value in
`vars.yml.example` changes from `homelab.local` to this real domain.

### cert-manager (wave 2)

- ACME `ClusterIssuer` against Let's Encrypt using the
  [**DNS-01** solver with the Cloudflare API](https://cert-manager.io/docs/configuration/acme/dns01/cloudflare/).
  DNS-01 (rather than HTTP-01) is what lets *private*,
  LAN-only services get real certificates: the challenge is answered with a
  TXT record in the public Cloudflare zone, so nothing needs to be reachable
  from the internet and no inbound port opens.
- Two issuers: `letsencrypt-staging` (default during bring-up per the
  [staging-environment guidance](https://letsencrypt.org/docs/staging-environment/),
  avoids prod [rate limits](https://letsencrypt.org/docs/rate-limits/)) and
  `letsencrypt-prod`.
- [Cloudflare API token](https://developers.cloudflare.com/fundamentals/api/get-started/create-token/)
  scoped to `Zone:DNS:Edit` on this one zone only, stored as a SealedSecret.
- One wildcard `Certificate` for `*.internal.<domain>` in the ingress
  namespace, referenced as the ingress controller's default TLS secret —
  individual apps then need no cert annotations at all. Per-app certs remain
  possible where isolation matters.
- Note for newcomers, documented in the component README: wildcard + DNS-01
  also avoids leaking every internal hostname into the public
  [Certificate Transparency logs](https://letsencrypt.org/docs/ct-logs/),
  which per-name certs would do.

### DNS for services

- Split-horizon: `*.internal.<domain>` resolves on the LAN to the ingress
  LoadBalancer IP via the local DNS server (router/Pi-hole —
  operator-specific, documented as a prerequisite). No public A/AAAA records
  exist for private services; the public zone carries only the ACME TXT
  challenges (transient) and whatever spec 0012 adds for public services.
- [external-dns](https://github.com/kubernetes-sigs/external-dns) is
  deliberately deferred; revisit if record count grows.

### kube-prometheus-stack (wave 3)

- [Helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
  via Kustomize: Prometheus, Grafana, Alertmanager, node-exporter,
  kube-state-metrics.
- Persistence on the `ceph-rbd` StorageClass (spec 0008); retention sized
  for homelab (e.g. 15 days / 20 GiB).
- Grafana behind ingress with a cert-manager certificate; admin password as
  a SealedSecret.
- Scrape the Proxmox hosts too
  ([pve-exporter](https://github.com/prometheus-pve/prometheus-pve-exporter))
  — ties the k8s and
  infrastructure learning together and gives the presentation a
  full-stack dashboard.

### Loki + Promtail (wave 3)

- Single-binary [Loki](https://grafana.com/docs/loki/latest/) mode with
  `ceph-rbd` persistence; Promtail DaemonSet.
- Grafana datasource pre-provisioned.

### Argo CD ingress (wave 4)

- Ingress + certificate for the Argo CD UI, closing spec 0007's
  port-forward-only gap.

## Implementation plan

1. MetalLB + ingress-nginx + cert-manager with the Let's Encrypt issuers
   (staging first, then prod) and the wildcard certificate; Argo CD ingress.
   (This makes the GitOps loop pleasant to use daily.)
2. kube-prometheus-stack, then Loki/Promtail.
3. pve-exporter and a combined "homelab overview" Grafana dashboard
   (Proxmox + Ceph + k8s) — this dashboard is a headline demo for the
   presentation (spec [0011](0011-meetup-presentation.md)).
4. Update the architecture doc's monitoring/network sections from
   aspirational to actual as each piece lands.

## Acceptance criteria

- [ ] `https://argocd.internal.<domain>` loads with a valid Let's Encrypt
      certificate — no browser warning on an untouched client machine — from
      a fresh bootstrap, via GitOps only.
- [ ] No inbound port on the router was opened to achieve any of this, and
      no private hostname resolves publicly.
- [ ] Grafana shows node metrics for all k8s nodes and all Proxmox hosts,
      and Ceph pool usage.
- [ ] Logs from any pod are queryable in Grafana within a minute of the pod
      starting.
- [ ] Everything survives the full teardown/rebuild test from spec 0007's
      acceptance criteria (monitoring history is expected to be lost —
      `Delete`-class storage — and that expectation is written down).
- [ ] A newcomer can read `applications/system/<component>/` and the
      applications README and understand each component's role without
      opening another repo.

## Open questions

- Cilium's built-in
  [L2 announcements](https://docs.cilium.io/en/stable/network/l2-announcements/)
  could replace MetalLB when
  `kubernetes_cni: cilium` — evaluate during the distro/CNI evaluation
  rather than blocking this spec; MetalLB works with both CNIs.
- Whether Alertmanager should notify anywhere at all in a homelab, or
  whether the Grafana dashboard is the alert channel.
