# Docs

Full-picture context: read `CLAUDE.md` at the repo root first. Everything
here is a deeper cut on one topic.

## Everyday

- **[OPERATIONS.md](OPERATIONS.md)** — health board, reconcile flow, app URLs, daily change loop.
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — failure symptoms and the concrete fix.
- **[COMMANDS.md](COMMANDS.md)** — copy-pasteable one-liners (Flux, kubectl, Talos, SOPS).

## Design & topology

- **[INGRESS.md](INGRESS.md)** — Envoy Gateway, MetalLB, CoreDNS, ExternalDNS, TLS wiring.
- **[SERVICES.md](SERVICES.md)** — host → namespace → backend service map.

## Adding and changing things

- **[ADDING-APPS.md](ADDING-APPS.md)** — step-by-step recipe to introduce a new app.
- **[AUTHENTIK-SSO.md](AUTHENTIK-SSO.md)** — how each app is wired (or should be wired) to Authentik.
- **[FINDASH-DEPLOY.md](FINDASH-DEPLOY.md)** — flip finance.passer.lan from placeholder to the real Dash app.

## Setup & recovery

- **[CLUSTER-SETUP.md](CLUSTER-SETUP.md)** — bring the cluster up from cold, or recover after a full outage.
- **[CONTROL-PLANE-FIX.md](CONTROL-PLANE-FIX.md)** — specific control-plane recovery incidents and their commands.
- **[AUTHENTIK.md](AUTHENTIK.md)** — first-run Authentik bootstrap and daily access.

## Backup

- **[VELERO-SETUP.md](VELERO-SETUP.md)** — Velero + MinIO on the `passer` Pi, one-time setup and full restore.
- **[velero-backups.md](velero-backups.md)** — schedule, targets, restore commands.
