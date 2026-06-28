# Ingress and DNS

This cluster exposes services on `passer.lan` through Envoy Gateway and uses
CoreDNS plus ExternalDNS to keep the names in sync.

TLS details now live in [Homelab HTTPS](homelab-https.md).

## Path

```text
LAN client -> Pi-hole -> CoreDNS -> Envoy Gateway -> service
```

## Fixed IPs

- Envoy Gateway: `192.168.178.240`
- CoreDNS: `192.168.178.241`

## Current Service Names

- `auth.passer.lan`
- `immich.passer.lan`
- `jellyfin.passer.lan`
- `nextcloud.passer.lan`
- `paperless.passer.lan`
- `podinfo.passer.lan`
- `vaultwarden.passer.lan`
- `longhorn.passer.lan`

## TLS

The HTTPS listener uses the locally generated `passer-lan-tls` Secret.
Browsers will warn until you manually trust that certificate on the client.

## Troubleshooting

If `nslookup immich.passer.lan` fails on a workstation but the cluster
resolver works, query CoreDNS directly:

```bash
nslookup immich.passer.lan 192.168.178.241
```

That points to a local DNS forwarding problem rather than a broken HTTPRoute.
