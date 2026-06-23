# Repository Structure

This repository is organized around GitOps, cluster infrastructure, application overlays, and Talos node assets.

## Top Level

```text
passercluster/
├── apps/
├── clusters/
├── docs/
├── infrastructure/
├── scripts/
├── talos/
├── talosconfig
├── CLUSTER-SETUP.md
├── COMMANDS.md
├── CURRENT-STATE.md
├── INGRESS.md
├── README.md
└── STRUCTURE.md
```

## Directory Roles

### `apps/`

Application manifests split into shared base definitions and environment-specific overlays.

- `apps/base/` contains namespaces, Helm repositories, HelmReleases, HTTPRoutes, PVCs, and secrets used by both environments.
- `apps/production/` contains production patches for release values and routes.
- `apps/staging/` contains staging-specific values and routes.

The app set currently includes:

- Immich
- Jellyfin
- Nextcloud
- Paperless-ngx
- Podinfo
- Vaultwarden

### `clusters/`

Flux bootstrap and cluster entrypoints.

- `clusters/production/` defines the production Flux `Kustomization` objects and source composition.
- `clusters/staging/` mirrors the production layout for the staging environment.

### `infrastructure/`

Cluster-wide controllers and resources.

- `infrastructure/controllers/` installs the core control plane add-ons such as cert-manager, Envoy Gateway, ExternalDNS, Longhorn, CloudNativePG, CoreDNS, and MetalLB.
- `infrastructure/configs/` defines the cluster resources those controllers need, including Gateway API objects, issuers, storage classes, and Longhorn placement.
- `infrastructure/velero/` and `infrastructure/velero-schedules/` hold the backup stack resources.

### `talos/`

Talos machine configuration, patches, and recovery artifacts.

- `talos/old-yaml/` contains previous machine configs.
- `talos/old-patches/` contains older patch fragments.
- `talos/patches/` contains the current Longhorn-related patches per node.
- `talos/recovered-talosconfig*/` contains recovery copies of Talos config.
- `talos/talosconfig*` contains local Talos client config snapshots and expired backups.

### `scripts/`

Operational helpers for storage validation, restore workflows, and health checks.

### `docs/`

Supplementary documentation that is not part of the main bootstrap path.

## Canonical GitOps Flow

1. `infrastructure/controllers/production/kustomization.yaml`
2. `infrastructure/configs/production/kustomization.yaml`
3. `apps/production/kustomization.yaml`

That order matters because apps depend on the controllers and cluster resources above them.

## Related Documentation

- [Repository map](docs/REPOSITORY_MAP.md)
- [Operations guide](docs/OPERATIONS.md)
- [Service map](docs/SERVICES.md)
- [Ingress and DNS](INGRESS.md)
- [Current state](CURRENT-STATE.md)
