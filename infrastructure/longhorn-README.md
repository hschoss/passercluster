# Longhorn Storage

## Architecture

```
192.168.178.200 / talos-2sm-xkd  control plane only, no Longhorn data
192.168.178.201 / talos-z8c-je7  NVMe performance-secondary  /var/mnt/longhorn-performance-secondary
192.168.178.202 / talos-3nt-pq2  NVMe performance-primary    /var/mnt/longhorn-performance
192.168.178.203 / talos-w45-5vh  HDD capacity + backup       /var/mnt/longhorn-capacity-* and /var/mnt/longhorn-backup-sdi
```

Longhorn is installed by Flux from `infrastructure/controllers/longhorn.yaml`. Configuration is applied after the Helm release by `infra-configs` in `clusters/production/infrastructure.yaml`.

## Storage Classes

| StorageClass | Use | Placement |
| --- | --- | --- |
| `longhorn-nextcloud-fast` | Nextcloud data, 1.5Ti target | Node 202 NVMe only |
| `longhorn-immich-fast` | Immich data, 1Ti target | Node 202 or Node 201 NVMe |
| `longhorn-jellyfin` | Jellyfin media, 4Ti target | Node 203 HDD capacity disks |
| `longhorn-backup` | Velero and backup data, 500Gi target | Node 203 `/dev/sdi` only |

All new application PVCs should select one of these classes directly. Legacy classes in `infrastructure/configs/storageclasses.yaml` remain for existing workloads and should be migrated when convenient.

## Talos Disk Patches

Apply the patch that matches each node:

```bash
talosctl apply-config --nodes 192.168.178.200 --file talos/passer-cp-01.yaml --config-patch @talos/patches/node-200-longhorn.patch.yaml
talosctl apply-config --nodes 192.168.178.201 --file talos/passer-w-01.yaml --config-patch @talos/patches/node-201-longhorn.patch.yaml
talosctl apply-config --nodes 192.168.178.202 --file talos/passer-w-02.yaml --config-patch @talos/patches/node-202-longhorn.patch.yaml
talosctl apply-config --nodes 192.168.178.203 --file talos/passer-w-03.yaml --config-patch @talos/patches/node-203-longhorn.patch.yaml
```

Run `scripts/longhorn-validate-disks.sh` before applying patches. Any partition warning must be treated as a blocker until the disk contents are verified.

## Snapshots And Backups

Recurring jobs are defined in `infrastructure/configs/longhorn-recurring-jobs.yaml`:

- `snapshot-performance-6h`: every 6 hours, retain 10.
- `snapshot-capacity-daily`: daily at 02:00, retain 10.
- `snapshot-backup-daily`: daily at 03:00, retain 10.
- `backup-s3-daily`: daily backup job for volumes that opt into the `external-backup` group.

The default S3 target is configured in the HelmRelease as `s3://longhorn-backups@minio-internal.internal:9000/longhorn` using the `longhorn-s3-creds` secret.

## Operations

- Dashboard: `http://longhorn.fritz.box` through `infrastructure/configs/longhorn-httproute.yaml`.
- Health check: run `scripts/longhorn-health-check.sh`.
- Restore: prefer the Longhorn UI for production restores; `scripts/longhorn-restore-from-backup.sh` is a starting point and must be tested with a non-critical backup first.

## Monitoring

`infrastructure/configs/longhorn-monitoring.yaml` contains `ServiceMonitor`, `PrometheusRule`, and a Grafana dashboard ConfigMap. It is intentionally not listed in `infrastructure/configs/kustomization.yaml` because this cluster does not currently have Prometheus Operator CRDs. Add it to the kustomization after installing those CRDs.

Alerts cover disk usage over 80%, degraded volumes, pending volumes, and backup failures.

## Troubleshooting

- Check Flux: `flux get kustomizations -A` and `flux get helmreleases -A`.
- Check Longhorn pods: `kubectl -n longhorn-system get pods -o wide`.
- Check disk tags: `kubectl -n longhorn-system get nodes.longhorn.io -o yaml`.
- Check StorageClass selectors: `kubectl get storageclass <name> -o yaml`.
- If a volume stays pending, confirm the StorageClass `nodeSelector` and `diskSelector` match the Longhorn node and disk tags.

## Upgrade Procedure

1. Read the Longhorn release notes for the target version.
2. Confirm all volumes are healthy and backups are current.
3. Update the chart version range in `infrastructure/controllers/longhorn.yaml`.
4. Reconcile Flux and monitor `longhorn-manager` logs.
5. Run `scripts/longhorn-health-check.sh`.
