# Velero Setup for `passer`

This document is the operational setup and restore guide for the cluster backup stack.

## Purpose

Velero protects the persistent application data that matters in this homelab:

- Nextcloud
- Immich
- Paperless-ngx
- Vaultwarden

Jellyfin media is intentionally excluded because it can be downloaded again.

The backup repository lives on the Raspberry Pi named `passer`:

- Hostname: `passer`
- LAN IP: `192.168.178.2`
- SSH user: `hannes`
- Backup endpoint: MinIO on `http://192.168.178.2:9000`
- Bucket: `velero`

The cluster does not store the backup repository on Kubernetes nodes.

## Current Design

The GitOps manifests configure Velero to:

- use the external S3-compatible MinIO endpoint on `passer`
- enable the node-agent
- use filesystem backups with the Kopia uploader
- run one daily backup schedule
- exclude Jellyfin media

This gives you deduplicated backups of PVC-backed application data while keeping the storage target off-cluster.

## What Is Backed Up

The daily Velero schedule includes these namespaces:

- `nextcloud`
- `immich`
- `paperless-ngx`
- `vaultwarden`

Velero backs up the Kubernetes objects for those namespaces and, because filesystem backups are enabled, the contents of their persistent volumes as well.

## What Is Not Backed Up

The following are intentionally out of scope:

- `jellyfin` media
- large re-downloadable media libraries
- ephemeral caches and temporary directories

If you later decide that Jellyfin config should be preserved, back up only the small config resources and keep the media PVC excluded.

## Deduplication

Deduplication is enabled through Velero’s Kopia-based backup path:

- `deployNodeAgent: true`
- `configuration.uploaderType: kopia`
- `defaultVolumesToFsBackup: true`

That means repeated filesystem backups are stored in a deduplicated repository instead of full copies every day.

## Repository Files

The relevant manifests live here:

- `infrastructure/configs/velero.yaml`
- `infrastructure/configs/velero-schedules.yaml`
- `infrastructure/configs/velero-credentials.secret.yaml`
- `infrastructure/configs/minio-credentials.secret.yaml`

The bucket bootstrap Job is part of `infrastructure/configs/velero.yaml`. It expects the Pi MinIO endpoint to already be reachable.

## Kubernetes Secrets

Two secrets are involved:

- `velero-credentials` for Velero’s S3 access
- `minio-credentials` for the bucket bootstrap Job

Keep both as SOPS-encrypted manifests in Git. Do not commit plaintext credentials.

If you need to recreate them manually, the secret data must match the MinIO credentials on `passer`.

Example shape only:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: velero-credentials
  namespace: velero
type: Opaque
stringData:
  cloud: |
    [default]
    aws_access_key_id=change-me
    aws_secret_access_key=change-me
```

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: minio-credentials
  namespace: velero
type: Opaque
stringData:
  MINIO_ROOT_USER: change-me
  MINIO_ROOT_PASSWORD: change-me
```

## Raspberry Pi Preparation

The Pi must be prepared before Flux can reconcile Velero successfully.

### 1. Set up SSH key access

Use an SSH key. Do not automate the password-based login flow.

```bash
ssh-keygen -t ed25519 -f ~/.ssh/passer_velero -C "hannes@passer"
ssh-copy-id -i ~/.ssh/passer_velero.pub hannes@192.168.178.2
ssh -i ~/.ssh/passer_velero hannes@192.168.178.2
```

If you already have a suitable key, reuse it.

### 2. Create the MinIO data directory

Example path:

```bash
mkdir -p /srv/minio/velero
```

### 3. Start MinIO on the Pi

Example using Docker:

```bash
docker run -d --name minio-velero \
  --restart unless-stopped \
  -p 9000:9000 \
  -p 9001:9001 \
  -v /srv/minio/velero:/data \
  -e MINIO_ROOT_USER=change-me \
  -e MINIO_ROOT_PASSWORD=change-me \
  quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z \
  server /data --console-address ":9001"
```

You can use a systemd unit instead if that fits your Pi setup better.

## Reconciliation Order

When applying the manifests through Flux, reconcile in this order:

1. `infra-controllers`
2. `infra-configs`
3. `infra-velero`
4. `infra-velero-schedules`
5. `apps`

Useful commands:

```bash
flux get kustomizations -A
flux reconcile kustomization infra-velero -n flux-system
flux reconcile kustomization infra-velero-schedules -n flux-system
```

If the Pi is not reachable yet, stop before reconciling and fix the Pi first.

## Schedule

The schedule runs once per day:

- Cron: `0 3 * * *`
- TTL: `336h`

The 14-day retention is intentional because the Raspberry Pi has only 256 GB and Nextcloud plus Immich can grow quickly.

## Status Checks

```bash
velero schedule get
velero backup get
velero backup describe <backup-name> --details
velero backup-location get
kubectl -n velero get pods
kubectl -n velero logs deploy/velero
kubectl get backupstoragelocation -A
kubectl -n velero get jobs,pods
kubectl -n velero logs job/velero-bucket-setup
```

If the backup repository is unhealthy, inspect the `BackupStorageLocation` and the velero pod logs first.

## Manual Backup

Trigger a one-off backup with the same scope as the daily schedule:

```bash
velero backup create manual-critical-apps-test \
  --include-namespaces nextcloud,immich,paperless-ngx,vaultwarden \
  --excluded-namespaces jellyfin \
  --default-volumes-to-fs-backup \
  --ttl 336h
```

After it finishes, inspect it:

```bash
velero backup describe manual-critical-apps-test --details
```

## Restore Workflow

### Restore into a temporary namespace

Use a temporary namespace mapping first so you can verify the restore safely.

Nextcloud example:

```bash
velero restore create nextcloud-restore-test \
  --from-backup <backup-name> \
  --namespace-mappings nextcloud:nextcloud-restore-test
```

Immich example:

```bash
velero restore create immich-restore-test \
  --from-backup <backup-name> \
  --namespace-mappings immich:immich-restore-test
```

Paperless example:

```bash
velero restore create paperless-restore-test \
  --from-backup <backup-name> \
  --namespace-mappings paperless-ngx:paperless-restore-test
```

Once the temporary restore looks good, you can perform the real restore intentionally and with care.

### Restore the original namespace

```bash
velero restore create --from-backup <backup-name>
```

Only do this when you are ready to replace the live data.

## Verification Checklist

After the schedule and BSL are healthy, confirm:

- `kubectl -n velero get backupstoragelocation`
- `kubectl -n velero get schedules`
- `kubectl -n velero get pods`
- `velero schedule get`
- `velero backup get`

If you want a quick end-to-end check, create a non-critical manual backup and verify that it appears in both the Velero CLI and the Kubernetes objects.

## Capacity Monitoring

The Pi only has 256 GB, so watch usage regularly:

```bash
ssh hannes@192.168.178.2 'df -h /srv/minio/velero 2>/dev/null || df -h /srv/minio 2>/dev/null || df -h'
```

Also monitor:

- the Velero logs
- the size of the MinIO data directory
- the number and age of backups

If the repository fills up, lower retention before backups start failing.

## Troubleshooting

### The bucket bootstrap Job never finishes

Check that MinIO is reachable on the Pi:

```bash
curl -fsS http://192.168.178.2:9000/minio/health/ready
```

If that fails, fix the Pi service first.

### Velero reports an unavailable BackupStorageLocation

Check:

```bash
kubectl -n velero get backupstoragelocation -o yaml
kubectl -n velero logs deploy/velero --tail=200
```

If the bucket does not exist, rerun the bootstrap Job after verifying the MinIO credentials.

### You need to rotate credentials

1. Update the Pi MinIO root credentials.
2. Update the SOPS-encrypted Kubernetes secrets.
3. Reconcile Flux.
4. Verify that the Velero HelmRelease returns to `Ready=True`.

Do not commit plaintext passwords or keys.
