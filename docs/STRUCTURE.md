# Repository Structure

The repository is organized around GitOps, cluster infrastructure, application
overlays, and Talos assets.

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
└── LICENSE
```

## Directory Roles

- `apps/` contains the shared app manifests and environment overlays.
- `clusters/` contains the Flux entry points for each environment.
- `infrastructure/` contains controllers and cluster-wide config.
- `scripts/` contains operational helpers.
- `docs/` contains the canonical Markdown documentation.
- `talos/` contains Talos machine config and recovery artifacts.

## Canonical GitOps Flow

1. `infrastructure/controllers/production/kustomization.yaml`
2. `infrastructure/configs/production/kustomization.yaml`
3. `apps/production/kustomization.yaml`
