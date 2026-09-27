# Authentik

## Purpose

Authentik is the primary browser login gateway for the homelab.
It will eventually sit in front of the hosted services through forward auth and, where supported, native OIDC or LDAP.

## First bootstrap

Authentik's documented first setup is done on port `9000`.
In this cluster the easiest way to reach that endpoint is port-forwarding the service:

```bash
kubectl -n authentik port-forward svc/authentik-server 9000:80
```

Then open:

```text
http://127.0.0.1:9000
```

If you want the repo to reconcile the Authentik release first and wait for it to become ready, use the helper script:

```bash
./scripts/authentik-bootstrap.sh
```

To reconcile and start the port-forward in one step:

```bash
./scripts/authentik-bootstrap.sh --port-forward
```

## Daily access

After bootstrap, the normal URL is:

```text
https://auth.passer.lan
```

## What this repo installs

- Authentik Helm chart from `charts.goauthentik.io`
- A dedicated `authentik` namespace
- A dedicated CloudNativePG database cluster
- SOPS-encrypted secrets for the Authentik secret key and database credentials
- A Gateway API route on `auth.passer.lan`

## Next step

After the initial admin account is created, wire the apps. Providers
and applications for Nextcloud, Immich, Paperless and Jellyfin are
already declared in `apps/base/authentik/authentik-blueprints.secret.yaml`
(SOPS-encrypted) — Authentik picks the blueprint up automatically from
`/blueprints/custom/` on every restart. The per-app side of the wiring
(what to set in Immich's admin UI, the Jellyfin plugin, the
Nextcloud bootstrap Job) is documented in
[`AUTHENTIK-SSO.md`](AUTHENTIK-SSO.md). Vaultwarden has no upstream
OIDC support and stays outside the SSO ring.
