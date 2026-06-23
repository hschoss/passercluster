# Service Map

This repository currently exposes private services through `https://<service>.passer.lan`.

## Core Endpoints

| Service | Namespace | URL | Notes |
| --- | --- | --- | --- |
| Immich | `immich` | `https://immich.passer.lan` | Route targets `immich-server:2283`. |
| Jellyfin | `jellyfin` | `https://jellyfin.passer.lan` | Media service. |
| Nextcloud | `nextcloud` | `https://nextcloud.passer.lan` | Host URL must match the app config. |
| Paperless-ngx | `paperless-ngx` | `https://paperless.passer.lan` | URL is set in the app values. |
| Podinfo | `podinfo` | `https://podinfo.passer.lan` | Good for ingress smoke tests. |
| Vaultwarden | `vaultwarden` | `https://vaultwarden.passer.lan` | Password manager. |
| Longhorn | `longhorn-system` | `https://longhorn.passer.lan` | Storage dashboard. |

## Staging Endpoints

Where staging overlays exist, the names are separate:

| Service | Namespace | URL |
| --- | --- | --- |
| Jellyfin staging | `jellyfin` | `https://jellyfin-staging.passer.lan` |
| Nextcloud staging | `nextcloud` | `https://nextcloud-staging.passer.lan` |
| Podinfo staging | `podinfo` | `https://podinfo-staging.passer.lan` |
| Vaultwarden staging | `vaultwarden` | `https://vaultwarden-staging.passer.lan` |

## DNS And TLS Facts

- Envoy Gateway listens on `192.168.178.240`.
- CoreDNS listens on `192.168.178.241`.
- The internal wildcard certificate is issued from `selfsigned-issuer`.
- Clients must trust the homelab root CA if they want a clean HTTPS experience.

## Quick Checks

```bash
nslookup immich.passer.lan
nslookup nextcloud.passer.lan
curl -I https://immich.passer.lan
curl -I https://nextcloud.passer.lan
```

If a service stops resolving, check the corresponding `HTTPRoute` first, then the app values, then `ExternalDNS`.
