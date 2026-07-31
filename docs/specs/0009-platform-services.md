# 0009 — Core platform services

**Status:** Draft
**Serves goals:** Fully GitOps-backed deployment; learning k8s; TLS/exposure
(goal 5: Let's Encrypt for private services)
**Depends on:** [0007 GitOps bootstrap](0007-gitops-bootstrap.md); monitoring
storage depends on [0008](0008-kubernetes-storage.md)
**Amended by:** [0006](0006-vm-platform.md) VMP-12 — the MetalLB pool is an
authoritative allocation rather than an example

## Context

The architecture doc names the target service stack (ingress, cert-manager,
Prometheus + Grafana, Loki) but the cluster has no load-balancer
implementation, no ingress, no TLS, and no observability. This spec defines
the minimum platform layer that end-user applications (and the GitOps
dashboard itself) build on. Everything here deploys through the GitOps tree
from spec 0007 under `applications/system/`.

Two components an earlier draft of this spec named are no longer viable and
have been replaced below:

- **ingress-nginx** was
  [retired by Kubernetes SIG Network](https://www.kubernetes.dev/blog/2025/11/12/ingress-nginx-retirement/):
  best-effort maintenance ended in March 2026 and there will be no further
  releases, bugfixes, or CVE fixes. The replacement is the
  [Gateway API](https://gateway-api.sigs.k8s.io/) with
  [Envoy Gateway](https://gateway.envoyproxy.io/) as the implementation.
- **Promtail** reached
  [end of life on 2 March 2026](https://grafana.com/docs/loki/latest/send-data/promtail/)
  and is replaced by [Grafana Alloy](https://grafana.com/docs/alloy/latest/).

Both were caught before any manifests existed, which is the cheapest possible
moment to change them.

## Goals

- Services get stable LoadBalancer IPs on the VM VLAN without a cloud
  provider.
- HTTPS ingress for everything with real, publicly trusted Let's Encrypt
  certificates (goal 5), the GitOps dashboard first — no browser warnings, no
  CA imports on client machines.
- Metrics, dashboards, and logs for the cluster and its workloads.
- Each component is a self-contained directory a newcomer can read in
  isolation (organization goal).

## Non-goals

- External/public exposure of any service — everything in this spec is
  private (LAN-only). Public exposure goes through Cloudflare per goal 5 and
  is specified in [0012](0012-public-exposure-cloudflare.md). Nothing here
  opens an inbound port on the router.
- Alerting routes (PagerDuty/Slack) — Alertmanager ships with the stack but
  routing stays default until there's an audience for alerts.
- Service mesh and pod security standards — future specs if a need or
  learning interest materializes. NetworkPolicy is now enforceable (spec
  [0016](0016-cluster-networking-cilium.md) makes Cilium the CNI); writing
  the actual baseline policies waits until there are applications to scope
  them to.

## Design

Components under `applications/system/`, ordered by `dependsOn` between their
Flux Kustomizations (spec [0007](0007-gitops-bootstrap.md)). Flux gates each
dependent on its dependency passing health checks, so the ordering below is
enforced rather than merely intended:

```
metallb ──┬──► envoy-gateway ──┬──► gitops-dashboard
          └──► cert-manager ───┘
storage (0008) ──► kube-prometheus-stack ──► loki + alloy
```

### MetalLB (depends on nothing)

- [L2 mode](https://metallb.io/concepts/layer2/) on the VM VLAN. The address
  pool is `192.168.100.240–192.168.100.250`, outside the node range — not an
  example, but the authoritative allocation in spec
  [0006](0006-vm-platform.md), VMP-12. `.240` is the shared
  Gateway and `.241` is Forgejo's git-over-SSH service (spec 0017, FORGE-07);
  `.251–.254` is reserved for growing this pool and nothing else. The manifest
  remains the single source, with the `vars.yml.example` comment pointing at it.

### Envoy Gateway (depends on MetalLB)

- [Envoy Gateway](https://gateway.envoyproxy.io/) as the
  [Gateway API](https://gateway-api.sigs.k8s.io/) implementation: the Gateway
  API CRDs plus the controller, installed from the pinned Helm chart via
  Kustomize.
- One shared `Gateway` (`GatewayClass: envoy-gateway`) in an `envoy-gateway`
  namespace with an HTTPS listener terminating the wildcard certificate below
  and an HTTP listener that redirects to it. Its `LoadBalancer` service takes
  the first MetalLB IP.
- Workloads attach with
  [`HTTPRoute`](https://gateway-api.sigs.k8s.io/api-types/httproute/) rather
  than `Ingress`.
  [ReferenceGrant](https://gateway-api.sigs.k8s.io/api-types/referencegrant/)
  lets routes in application namespaces bind to the shared Gateway without
  each namespace owning a load-balancer IP.
- Rationale for Gateway API over another Ingress controller: the resource
  model is upstream Kubernetes API, so replacing the *implementation* later
  (Cilium Gateway API — see open questions) is a `GatewayClass` change rather
  than rewriting every application manifest. That portability is exactly what
  the ingress-nginx retirement cost everyone who had standardized on
  controller-specific annotations.

### Domain prerequisite

Goal 5 requires publicly trusted certificates, which requires a real
registered domain — `.local` names cannot get Let's Encrypt certs. The
domain's DNS is hosted on Cloudflare (also a prerequisite for
[0012](0012-public-exposure-cloudflare.md)). Private services live under a
dedicated subdomain, e.g. `*.internal.<domain>`; the `domain_name` value in
`vars.yml.example` changes from `homelab.local` to this real domain.

### cert-manager (depends on MetalLB)

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
  scoped to `Zone:DNS:Edit` on this one zone only, stored as a SOPS-encrypted
  Secret.
- One wildcard `Certificate` for `*.internal.<domain>` in the
  `envoy-gateway` namespace, referenced by the shared Gateway's HTTPS
  listener — individual apps then need no certificate configuration at all.
  Per-app certs remain possible on their own listener where isolation
  matters.
- Note for newcomers, documented in the component README: wildcard + DNS-01
  also avoids leaking every internal hostname into the public
  [Certificate Transparency logs](https://letsencrypt.org/docs/ct-logs/),
  which per-name certs would do.

### DNS for services

- Split-horizon: `*.internal.<domain>` resolves on the LAN to the Gateway's
  LoadBalancer IP via the local DNS server (router/Pi-hole —
  operator-specific, documented as a prerequisite). No public A/AAAA records
  exist for private services; the public zone carries only the ACME TXT
  challenges (transient) and whatever spec 0012 adds for public services.
- [external-dns](https://github.com/kubernetes-sigs/external-dns) is
  deliberately deferred; revisit if record count grows.

### kube-prometheus-stack (depends on storage)

- [Helm chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
  via Kustomize: Prometheus, Grafana, Alertmanager, node-exporter,
  kube-state-metrics.
- Persistence on the `ceph-rbd` StorageClass (spec 0008); retention sized
  for homelab (e.g. 15 days / 20 GiB).
- Grafana behind an `HTTPRoute` on the shared Gateway; admin password as a
  SOPS-encrypted Secret.
- Scrape the Proxmox hosts too
  ([pve-exporter](https://github.com/prometheus-pve/prometheus-pve-exporter))
  — ties the k8s and
  infrastructure learning together and gives the presentation a
  full-stack dashboard.

### Loki + Grafana Alloy (depends on kube-prometheus-stack)

- Single-binary [Loki](https://grafana.com/docs/loki/latest/) mode with
  `ceph-rbd` persistence.
- [Grafana Alloy](https://grafana.com/docs/alloy/latest/) DaemonSet as the
  log collector, shipping to Loki. Alloy replaces Promtail, which reached end
  of life on 2 March 2026; it is Grafana's OpenTelemetry Collector
  distribution, so the same agent can later carry metrics and traces if the
  need appears — that consolidation is not part of this spec, which keeps
  Prometheus scraping as-is.
- Grafana datasource pre-provisioned.

### GitOps dashboard (depends on Envoy Gateway and cert-manager)

Flux ships no UI, so spec 0007 leaves the cluster CLI-only. This closes that
gap: deploy one Flux dashboard and give it an `HTTPRoute` on the shared
Gateway.

- [Headlamp](https://headlamp.dev/) with its Flux plugin is the default
  choice — it renders the reconciliation tree *and* is a general-purpose
  cluster UI, so it earns its keep beyond GitOps.
  [Capacitor](https://github.com/gimlet-io/capacitor) is the smaller
  alternative if Headlamp proves heavier than it's worth.
- TLS terminates once, at the Gateway; the dashboard serves plain HTTP behind
  it.
- Access control matters here — a cluster dashboard is a privileged surface.
  It stays LAN-only (spec [0012](0012-public-exposure-cloudflare.md)
  explicitly excludes it from public exposure) and uses the dashboard's own
  OIDC or token authentication, not an unauthenticated route.

## Implementation plan

1. MetalLB + Envoy Gateway + cert-manager with the Let's Encrypt issuers
   (staging first, then prod), the wildcard certificate, and the shared
   Gateway; the GitOps dashboard `HTTPRoute`. (This makes the GitOps loop
   pleasant to use daily.)
2. kube-prometheus-stack, then Loki + Alloy.
3. pve-exporter and a combined "homelab overview" Grafana dashboard
   (Proxmox + Ceph + k8s) — this dashboard is a headline demo for the
   presentation (spec [0011](0011-meetup-presentation.md)).
4. Update the architecture doc's monitoring/network sections from
   aspirational to actual as each piece lands.

## Acceptance criteria

- [ ] `https://flux.internal.<domain>` loads with a valid Let's Encrypt
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
- [ ] No component in this spec is one whose upstream has announced
      retirement or end of life. Re-checked whenever this spec is touched.

## Open questions

- ~~Should Cilium replace MetalLB and Envoy Gateway?~~ **Decided: no** — see
  spec [0016](0016-cluster-networking-cilium.md). Cilium is the CNI with
  kube-proxy replacement enabled, so both of its
  [L2 announcements](https://docs.cilium.io/en/stable/network/l2-announcements/)
  and [Gateway API](https://docs.cilium.io/en/stable/network/servicemesh/gateway-api/gateway-api/)
  features are available, and both are deliberately left unused: collapsing
  them puts pod networking, Service IPs and ingress in one blast radius, and
  Cilium's L2 announcements cannot coexist with
  `externalTrafficPolicy: Local`, which is how this stack gets real client
  addresses into Grafana. Revisitable as a one-cluster experiment.
- Whether Alertmanager should notify anywhere at all in a homelab, or
  whether the Grafana dashboard is the alert channel.
