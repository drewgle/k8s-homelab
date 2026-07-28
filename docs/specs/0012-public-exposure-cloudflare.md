# 0012 — Public service exposure via Cloudflare

**Status:** Draft
**Serves goals:** TLS/exposure (goal 6: public services through Cloudflare);
fully GitOps-backed deployment
**Depends on:** [0007 GitOps bootstrap](0007-gitops-bootstrap.md);
[0009 platform services](0009-platform-services.md) (domain on Cloudflare,
ingress, cert-manager)

## Context

Goal 6 splits service exposure into two classes: private services get Let's
Encrypt certificates and stay LAN-only (spec 0009), and public services are
exposed through Cloudflare. This spec defines the public half: how a workload
in the cluster becomes reachable from the internet without opening a single
inbound port on the home router, and what the promotion path from private to
public looks like.

## Goals

- Public services are reachable at `<name>.<domain>` from anywhere, fronted
  by Cloudflare (TLS termination at the edge, home IP never exposed, DDoS
  and bot filtering included).
- Zero inbound ports on the router — outbound-only connectivity.
- Making a service public is a git commit: one manifest change, reconciled
  by Argo CD, no Cloudflare dashboard clicking.
- **Private by default.** Nothing becomes public implicitly; the public
  path requires an explicit, reviewable declaration.

## Non-goals

- Exposing the Proxmox/Ceph management plane or the Argo CD UI publicly —
  management stays LAN/VPN-only regardless of this spec.
- Email, non-HTTP TCP/UDP services (game servers etc.) — Cloudflare Tunnel
  can carry arbitrary TCP but each case needs its own review; out of scope
  until one exists.
- Replacing the private path: a public service may *also* remain reachable
  internally via its `*.internal.<domain>` name.

## Design

### Cloudflare Tunnel (cloudflared)

A [`cloudflared` Deployment](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/deployment-guides/kubernetes/)
(2 replicas) in the cluster maintains outbound-only connections to
Cloudflare's edge (see the
[Cloudflare Tunnel docs](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/)).
Public hostnames map through
the tunnel to in-cluster services. This is the piece that keeps the router
closed: Cloudflare terminates public TLS at the edge and delivers traffic
down the established tunnel.

- Deployed from `applications/system/cloudflare-tunnel/` via GitOps.
- Tunnel credentials (tunnel token) as a SealedSecret.
- Tunnel ingress rules are **declared in the ConfigMap in git** (not
  dashboard-managed), so the set of public hostnames is version-controlled
  and reviewable — this is the "explicit declaration" that makes a service
  public.
- Traffic from cloudflared targets the existing ingress-nginx service, so
  routing/middleware stays in one place; the tunnel hop to the ingress
  controller uses the wildcard cert from spec 0009 (`noTLSVerify` stays
  off).

### DNS

Each public hostname gets a
[proxied (orange-cloud) CNAME](https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/routing-to-tunnel/dns/)
to the tunnel's
`<tunnel-id>.cfargotunnel.com` address. Created via the tunnel ingress
config (`cloudflared` manages the records) or committed Terraform-free via
the same ConfigMap — implementation decides, spec updated with the outcome.
Public and private names never overlap: `app.<domain>` is public,
`app.internal.<domain>` is private, and `*.internal.<domain>` never appears
in the public zone (spec 0009's split-horizon rule).

### Access control

- [**Cloudflare Access**](https://developers.cloudflare.com/cloudflare-one/policies/access/)
  in front of any public service that has no strong
  built-in auth: SSO gate at the edge (email OTP / GitHub login), policies
  declared alongside the tunnel config. Free tier covers homelab scale.
- Services with real auth of their own may opt out of Access, recorded in
  the service's directory README.

### Certificates and the two TLS zones

Public clients see a Cloudflare edge certificate; the cluster-side hop uses
the Let's Encrypt wildcard from spec 0009. Documented explicitly in the
component README because "who terminates TLS where" is the most common
point of confusion in this architecture:

```
Browser ──TLS (Cloudflare edge cert)──▶ Cloudflare ──tunnel──▶ cloudflared
        ──TLS (Let's Encrypt wildcard)──▶ ingress-nginx ──▶ Service
```

### Promotion checklist (private → public)

Documented in `applications/README.md`; making a service public requires a
PR that:

1. Adds the hostname to the tunnel ingress ConfigMap.
2. Adds a Cloudflare Access policy (or a README note on why the app's own
   auth suffices).
3. States what data the service exposes and why public access is needed.

## Implementation plan

1. Create the tunnel + scoped API token (one-time `cloudflared tunnel
   create`, documented; credentials sealed).
2. `applications/system/cloudflare-tunnel/` with cloudflared, the ConfigMap,
   and the SealedSecret; wire into the app-of-apps tree.
3. First public service end-to-end — a deliberately harmless one (e.g. a
   static "about this homelab" page, which doubles as presentation
   material) behind Cloudflare Access.
4. Promotion checklist in `applications/README.md`; update the architecture
   doc's network section with the two-TLS-zones diagram.

## Acceptance criteria

- [ ] The demo service is reachable publicly at `<name>.<domain>` with a
      valid certificate, from a network that is not the LAN.
- [ ] The router has zero inbound port-forward rules; the home IP appears
      nowhere in public DNS for the domain.
- [ ] Cloudflare Access challenges an anonymous visitor before the demo
      service loads.
- [ ] Removing the hostname from the ConfigMap in git (only that) makes the
      service unreachable publicly within one reconcile cycle.
- [ ] Full teardown/rebuild (spec 0007's criterion) restores public
      reachability without touching the Cloudflare dashboard.

## Open questions

- Whether tunnel DNS records should be managed by cloudflared itself or
  pinned manually — decide when implementing, favoring whichever leaves the
  git repo as the source of truth.
- Cloudflare free-tier limits (request size, streaming) if a media-heavy
  service is ever promoted — evaluate per service at promotion time.
