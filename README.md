# Passercluster

Passercluster is the GitOps repository for the homelab and production Kubernetes stack I run on Talos. Flux watches this repo and reconciles infrastructure, ingress, storage, and application workloads into the cluster.

## What Lives Here

- Talos machine configuration and recovery notes under `talos/`, plus the tracked top-level `talosconfig` snapshot
- Flux bootstrap and cluster entrypoints under `clusters/`
- Shared infrastructure controllers and cluster resources under `infrastructure/`
- Application base manifests and per-environment overlays under `apps/`
- Operational docs and runbooks in the root and `docs/`

## Current Stack

- Talos Linux
- Flux CD
- Envoy Gateway and Gateway API HTTPRoutes
- cert-manager with an internal CA
- MetalLB for static LAN LoadBalancer IPs
- CoreDNS and ExternalDNS for `passer.lan`
- Longhorn for persistent storage
- CloudNativePG for PostgreSQL
- Velero and MinIO for backups
- Immich, Nextcloud, Jellyfin, Vaultwarden, Paperless-ngx, and Podinfo

## Repository Map

- [Repository map](docs/REPOSITORY_MAP.md)
- [Operations guide](docs/OPERATIONS.md)
- [Service map](docs/SERVICES.md)

## Existing Runbooks

- [Cluster setup](CLUSTER-SETUP.md)
- [Ingress and DNS](INGRESS.md)
- [Current state](CURRENT-STATE.md)
- [Longhorn notes](infrastructure/longhorn-README.md)
- [Commands](COMMANDS.md)
- [Homelab setup notes](docs/HOMELAB_SETUP.md)

## Working On The Repo

1. Edit the manifests in `apps/`, `infrastructure/`, or `clusters/`.
2. Reconcile the affected Flux kustomization.
3. Verify the relevant services with `kubectl`, `flux`, and the service URLs in `docs/SERVICES.md`.
4. Keep local Talos recovery dumps, credentials, and other machine-specific artifacts out of Git.

## Canonical Entry Points

- `clusters/production/infrastructure.yaml`
- `clusters/production/apps.yaml`
- `infrastructure/controllers/production/kustomization.yaml`
- `infrastructure/configs/production/kustomization.yaml`
- `apps/production/kustomization.yaml`
