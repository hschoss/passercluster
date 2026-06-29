# Repository Map

This document maps the repository tree to its purpose so the next cleanup or push can be done without re-discovering the layout.

## Root Files

| Path | Purpose |
| --- | --- |
| `README.md` | Landing page for the repository and entry point to the other docs. |
| `STRUCTURE.md` | High-level tree and GitOps flow. |
| `CLUSTER-SETUP.md` | Talos and Flux bootstrap notes for the production cluster. |
| `CURRENT-STATE.md` | Snapshot of the latest known healthy or unhealthy cluster state. |
| `COMMANDS.md` | Short command reference. |
| `INGRESS.md` | DNS and ingress model for `passer.lan`. |
| `LICENSE` | Project license. |
| `talosconfig` | Tracked Talos client config snapshot used for cluster access. |
| `new-struc.md` | Scratch note; not part of the canonical documentation set. |

## `apps/`

The `apps/` tree holds all application manifests.

### `apps/base/`

Shared app definitions live here. Each app directory usually contains:

- `namespace.yaml` for the namespace
- `repository.yaml` or `oci-repository.yaml` for the Helm source
- `release.yaml` for the HelmRelease
- `httproute.yaml` for ingress exposure
- `pvc.yaml` or app-specific secrets when needed

Current base applications:

- `immich/` - Immich server, PostgreSQL, Redis, and the library PVC
- `jellyfin/` - Jellyfin media server
- `nextcloud/` - Nextcloud and its URL, trusted domain, and database settings
- `paperless-ngx/` - Paperless-ngx and export job support
- `podinfo/` - Simple test application for ingress and Flux checks
- `vaultwarden/` - Vaultwarden password manager

### `apps/production/`

Production overlays patch the base app manifests with production-specific values, hostnames, storage classes, and secrets.

### `apps/staging/`

Staging overlays mirror the production layout where staging variants exist.

### `apps/e2e/`

Lightweight CI-only overlay used by the GitHub Actions Flux smoke test. It keeps the test path focused on a single routable app instead of the full staging workload set.

## `clusters/`

Cluster-level Flux entry points.

- `clusters/production/` contains the production `Kustomization` objects that pull from `infrastructure/` and `apps/`.
- `clusters/staging/` contains the staging equivalent.
- `clusters/e2e/` contains the lightweight CI reconciliation path.
- `flux-system/` under each cluster holds the Flux bootstrap resources.

## `infrastructure/`

Shared cluster infrastructure and platform resources.

### `infrastructure/controllers/`

Controller installation manifests. The current controller set includes:

- `cert-manager.yaml`
- `cloudnative-pg.yaml`
- `coredns.yaml`
- `envoy-gateway.yaml`
- `external-dns.yaml`
- `longhorn.yaml`
- `metallb.yaml`

Production and staging overlays keep the controller stacks environment-specific where needed.

### `infrastructure/configs/`

Cluster resources that depend on the controllers being present.

- `cluster-issuers.yaml` - internal CA and issuer resources
- `gateway.yaml` - Gateway API and Envoy Gateway wiring
- `metallb-config.yaml` - address pool and advertisement settings
- `storageclasses.yaml` - storage classes for workloads
- `longhorn-application-pvcs.yaml` - PVC templates for app storage
- `longhorn-node-labels.yaml` - node placement labels for Longhorn
- `longhorn-recurring-jobs.yaml` - snapshot and backup schedules
- `longhorn-storage-classes.yaml` - Longhorn-backed storage classes
- `longhorn-httproute.yaml` - Longhorn dashboard exposure
- `longhorn-monitoring.yaml` - monitoring resources, kept separate until the needed CRDs exist

### `infrastructure/velero/`

Velero backup resources. The current backup stack points to the external MinIO endpoint on `passer` (`192.168.178.2`) instead of running a bucket store inside the cluster.

### `infrastructure/velero-schedules/`

Velero schedule resources that are deployed after the core backup stack. The daily schedule backs up the stateful application namespaces and intentionally excludes Jellyfin media.

## `scripts/`

Helper scripts for operational tasks.

- `longhorn-health-check.sh`
- `longhorn-restore-from-backup.sh`
- `longhorn-validate-disks.sh`
- `validate.sh`

## `talos/`

Talos-specific configuration, node patches, and recovery artifacts.

- `patches/` - current node patch fragments
- `old-patches/` - archived patch fragments
- `old-yaml/` - archived Talos machine configs
- `recovered-talosconfig/` and `recovered-talosconfig-2/` - recovered Talos client configs
- `talosconfig*` - local Talos client config snapshots and expired backups
- `FIX.md`, `TASK.MD`, `CONTROL-PLANE-FIX.md` - recovery and incident notes

## `docs/`

Supplementary documentation.

- [`HOMELAB_SETUP.md`](HOMELAB_SETUP.md) - setup notes for the homelab stack
- [`velero-backups.md`](velero-backups.md) - Velero backup and restore guide
- [`infrastructure/longhorn-README.md`](../infrastructure/longhorn-README.md) - Longhorn-specific storage notes

## Local-Only Artifacts

These files and directories should stay local unless you intentionally want to publish them:

- `talos/talosconfig*`
- `talos/recovered-talosconfig*/`
- `talos/talosconfig.expired-*`
- `.claude/`
- `talos/.claude/`

## Recommended Push Set

For a clean GitHub push, the canonical docs and manifests are usually:

- `README.md`
- `STRUCTURE.md`
- `docs/REPOSITORY_MAP.md`
- `docs/OPERATIONS.md`
- `docs/SERVICES.md`
- the relevant manifests under `apps/`, `clusters/`, and `infrastructure/`
