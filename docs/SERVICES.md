# Service map

Every private URL served by the cluster and where it terminates.

## Production

| Service        | URL                              | Namespace       | Backend Service : port     | Notes                                             |
|----------------|----------------------------------|-----------------|----------------------------|---------------------------------------------------|
| Landing page   | `https://passer.lan`             | `passer-home`   | `passer-home:80`           | Static nginx, links to services + `/docs/`        |
| Findash        | `https://finance.passer.lan`     | `finance`       | `finance-placeholder:80` (placeholder) → `findash:5000` (when image is built) | See `FINDASH-DEPLOY.md`         |
| Authentik      | `https://auth.passer.lan`, `https://authentik.passer.lan` | `authentik`     | `authentik-server:80`      | Two hostnames, one Service; SSO for the stack     |
| Nextcloud      | `https://nextcloud.passer.lan`   | `nextcloud`     | `nextcloud:8080`           | Host URL must match chart values                  |
| Immich         | `https://immich.passer.lan`      | `immich`        | `immich-server:2283`       | Media library and mobile app                      |
| Jellyfin       | `https://jellyfin.passer.lan`    | `jellyfin`      | `jellyfin:8096`            | Media streaming, config on `talos-8bp-pih`         |
| Paperless-ngx  | `https://paperless.passer.lan`   | `paperless-ngx` | `paperless-ngx:8000`       | Document archive                                  |
| Vaultwarden    | `https://vaultwarden.passer.lan` | `vaultwarden`   | `vaultwarden:80`           | Password manager, no SSO available                |
| Longhorn UI    | `https://longhorn.passer.lan`    | `longhorn-system` | `longhorn-frontend:80`   | Storage dashboard                                 |
| Podinfo        | `https://podinfo.passer.lan`     | `podinfo`       | `podinfo:9898`             | Smoke-test app for gateway / TLS / DNS            |

Every one of these is served by the same `Gateway/envoy` in
`envoy-gateway-system` on `192.168.178.240` — see
[INGRESS.md](INGRESS.md).

## Staging overlays

Wherever `apps/staging/` defines an overlay, the hostname is a
separate one:

| Service              | URL                                 |
|----------------------|-------------------------------------|
| Jellyfin staging     | `https://jellyfin-staging.passer.lan`   |
| Nextcloud staging    | `https://nextcloud-staging.passer.lan`  |
| Podinfo staging      | `https://podinfo-staging.passer.lan`    |
| Vaultwarden staging  | `https://vaultwarden-staging.passer.lan`|

## Facts to remember

- Envoy Gateway: `192.168.178.240`
- CoreDNS: `192.168.178.241`
- The HTTPS listener uses `passer-lan-tls` (SANs `passer.lan`, `*.passer.lan`).
- Trust `secrets/passer-lan.crt` on every daily-use client machine.
- If a host stops resolving, check the HTTPRoute first, then the chart
  values, then `external-dns` logs. See
  [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for concrete symptoms.

## Quick smoke test

```bash
for h in passer.lan nextcloud.passer.lan immich.passer.lan jellyfin.passer.lan \
         paperless.passer.lan vaultwarden.passer.lan auth.passer.lan \
         longhorn.passer.lan podinfo.passer.lan finance.passer.lan; do
  printf '%-32s ' "$h"
  curl -skI --resolve $h:443:192.168.178.240 https://$h/ --max-time 5 | head -1
done
```

Expect `HTTP/2 200`, `HTTP/2 302` (redirect to a login), or `HTTP/2 404`
where the app hasn't finished bootstrapping yet — but never a
connection error.
