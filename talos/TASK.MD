# Task: Re-establish LAN DNS for Homelab Services via Pi-hole

## Objective

Make Kubernetes homelab services reachable on the LAN with names like:

- `immich.passer.lan`
- `nextcloud.passer.lan`
- `grafana.passer.lan`
- `api.passer.lan`
- `app.passer.lan`

Write a Markdown document in the home directory of user `hannes` on server `passer` (`192.168.178.2`) that explains:

- what was changed
- how DNS resolution works
- how to add a new domain
- how to delete a domain

## Current Findings

### Raspberry Pi / Pi-hole

- Host: `passer` at `192.168.178.2`
- Access method requested by user: `ssh hannes@192.168.178.2`
- Pi-hole is already running as Docker container `pihole`
- Pi-hole data path:
  - `/srv/docker/pihole/etc-pihole`
  - `/srv/docker/pihole/etc-dnsmasq.d`

Current Pi-hole DNS config found on the server:

- `/srv/docker/pihole/etc-dnsmasq.d/99-passer-home-arpa.conf`
  - `address=/.passer.lan/192.168.178.240`
- `/srv/docker/pihole/etc-pihole/custom.list`
  - static records for `immich`, `paperless`, `nextcloud`, `jellyfin`, `longhorn`, `velero`
  - all currently under `passer.lan`

### Kubernetes / GitOps repo

- The cluster uses `Envoy Gateway` and `HTTPRoute`
- The active design in the repo uses:
  - `Envoy Gateway`
  - `Gateway API`
  - `HTTPRoute`
  - `MetalLB`
  - `ExternalDNS`
  - in-cluster `CoreDNS`

Relevant current repo settings already found:

- Envoy LoadBalancer IP: `192.168.178.240`
- CoreDNS LoadBalancer IP: `192.168.178.241`
- Current Gateway hostname wildcard: `*.passer.lan`
- Current ExternalDNS domain filter: `passer.lan`
- Current application routes such as:
  - `immich.passer.lan`
  - `nextcloud.passer.lan`

### Known blocker from previous run

- The cluster control-plane endpoint and service IPs were unreachable during inspection:
  - `192.168.178.200`
  - `192.168.178.240`
  - `192.168.178.241`

That means final live validation may fail until cluster networking or node availability is restored.

## Required End State

### DNS

- LAN clients using Pi-hole must resolve `*.passer.lan` to the Kubernetes gateway entrypoint
- Resolution should be maintainable without manually editing many duplicate host records

### Kubernetes routing

- The cluster gateway must accept `*.passer.lan`
- Application HTTP routes must expose `passer.lan` hostnames
- DNS automation, if kept, must publish or support `passer.lan`
- TLS configuration must match the chosen hostname pattern

### Documentation

- A Markdown file must be created in `~hannes` on `passer`
- It must explain the architecture and the operational steps for adding/removing a domain

## Implementation Plan

1. Verify cluster reachability again before changing manifests.
2. Inspect the full set of repo files that still reference:
   - `passer.lan`
   - `.lan`
3. Decide the DNS model:
   - preferred: use one wildcard-style Pi-hole forwarding/config pattern for `passer.lan`
   - avoid per-service static records where possible
4. Update the GitOps manifests so the cluster itself expects `passer.lan`:
   - Gateway wildcard hostname
   - ExternalDNS domain filters
   - CoreDNS zone configuration if still used
   - all production `HTTPRoute` hostnames
   - any staging/base routes that must stay consistent
   - certificate references and comments where hostname-specific
5. Update Pi-hole config on `passer`:
   - remove or replace `passer.lan` records
   - add `passer.lan` handling
   - restart/reload the Pi-hole container
6. Validate from the Pi and, if possible, from the local machine:
   - `nslookup immich.passer.lan`
   - `nslookup nextcloud.passer.lan`
   - `curl -I http://immich.passer.lan`
   - HTTPS checks if TLS is already aligned
7. Write final documentation to `~hannes/<name>.md` on `passer`.

## Preferred Technical Approach

Use Pi-hole only for DNS and keep Kubernetes ingress/routing in the cluster.

That means:

- Pi-hole should not be treated as the ingress controller
- Pi-hole should resolve or forward `passer.lan`
- Envoy Gateway should remain the actual entrypoint for HTTP/HTTPS traffic
- Application exposure should stay declarative in Kubernetes via `HTTPRoute`

## Files Likely To Change

In the repo above `talos/`:

- `../infrastructure/configs/production/gateway.yaml`
- `../infrastructure/controllers/production/external-dns.yaml`
- `../infrastructure/controllers/production/coredns.yaml`
- `../apps/production/*-httproute.yaml`
- any supporting values/docs still naming `passer.lan` or `.lan`

On the Raspberry Pi:

- `/srv/docker/pihole/etc-dnsmasq.d/*.conf`
- `/srv/docker/pihole/etc-pihole/custom.list`
- `~/pihole-*.md` documentation file

## Validation Criteria

The task is complete only if:

- Pi-hole resolves the requested `passer.lan` names
- the Kubernetes gateway accepts those hostnames
- at least the key services resolve consistently:
  - `immich.passer.lan`
  - `nextcloud.passer.lan`
- the documentation exists in `~hannes` on `passer`
- the documentation includes add/delete instructions

## Risks

- The cluster may still be offline or partially unreachable
- Existing `.lan` or `passer.lan` clients may break if migration is abrupt
- TLS may fail until certificates and client trust are updated
- Flux-managed changes may require commit/push and successful reconciliation before they become live
