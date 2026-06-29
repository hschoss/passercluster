# Velero Backups to `passer`

This repository uses Velero to back up the important persistent application data into a separate Raspberry Pi named `passer`.

## Backup Target

- Hostname: `passer`
- LAN IP: `192.168.178.2`
- SSH user: `hannes`
- Storage backend: MinIO on the Pi, exposed on `http://192.168.178.2:9000`
- Bucket: `velero`
- Repository path on the Pi: the MinIO data directory you choose locally, for example `/srv/minio/velero`

The cluster does not store backup data on Kubernetes nodes. Velero writes to the external S3-compatible endpoint on the Raspberry Pi.

## What Is Backed Up

The daily schedule currently includes these namespaces:

- `nextcloud`
- `immich`
- `paperless-ngx`
- `vaultwarden`

These namespaces contain the persistent data that matters for day-to-day recovery. Velero also backs up PVC contents with filesystem backups, so the application data on the volumes is included.

## What Is Excluded

- `jellyfin` is excluded on purpose
- Jellyfin media is intentionally not part of the backup set because it can be downloaded again
- Temporary or re-downloadable media/cache data is not included

If you later decide that Jellyfin config is worth preserving, add only the small config resources and keep the media PVC out of scope.

## Deduplication

Deduplication is enabled through Velero's filesystem backup path and the Kopia uploader:

- `deployNodeAgent: true`
- `configuration.uploaderType: kopia`
- `defaultVolumesToFsBackup: true`

That means volume backups are stored in a deduplicated repository rather than as full raw copies each day.

## Raspberry Pi Preparation

The Pi must run SSH key-based access and MinIO before the cluster can create backups.

### 1. Set up SSH keys

On your workstation:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/passer_velero -C "hannes@passer"
ssh-copy-id -i ~/.ssh/passer_velero.pub hannes@192.168.178.2
ssh -i ~/.ssh/passer_velero hannes@192.168.178.2
```

If you already have a suitable SSH key, reuse it instead of creating a new one.

### 2. Create the MinIO data directory

On the Pi:

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

Keep the real credentials out of Git. If you want to use the existing encrypted Kubernetes secret for bootstrap, make the Pi MinIO root credentials match the values used there.

## Cluster Configuration

The cluster resources live under `infrastructure/configs/` and are managed by Flux:

- `infrastructure/configs/velero.yaml`
- `infrastructure/configs/velero-schedules.yaml`
- `infrastructure/configs/velero-credentials.secret.yaml`
- `infrastructure/configs/minio-credentials.secret.yaml`

Velero uses the `velero-credentials` secret for S3 access. The bucket bootstrap Job uses the `minio-credentials` secret to create the bucket on the Pi.

## Daily Schedule

The schedule runs once per day at 03:00 local time and keeps backups for 14 days:

- schedule: `0 3 * * *`
- TTL: `336h`

The shorter retention is intentional because the Pi has only 256 GB of backup capacity and Nextcloud plus Immich can grow quickly.

## Status Checks

Use these commands to inspect the backup stack:

```bash
velero schedule get
velero backup get
velero backup describe <backup-name> --details
kubectl -n velero get pods
kubectl -n velero logs deploy/velero
kubectl get backupstoragelocation -A
```

To check the bucket bootstrap Job:

```bash
kubectl -n velero get jobs,pods
kubectl -n velero logs job/velero-bucket-setup
```

## Manual Backup

Trigger a one-off backup with the same scope as the schedule:

```bash
velero backup create manual-critical-apps-test \
  --include-namespaces nextcloud,immich,paperless-ngx,vaultwarden \
  --excluded-namespaces jellyfin \
  --default-volumes-to-fs-backup \
  --ttl 336h
```

## Restore Examples

### Restore the latest backup

```bash
velero restore create --from-backup <backup-name>
```

### Restore into a temporary namespace for testing

Example for Nextcloud:

```bash
velero restore create nextcloud-restore-test \
  --from-backup <backup-name> \
  --namespace-mappings nextcloud:nextcloud-restore-test
```

After the restore finishes, inspect the workload and then delete the test namespace when you are done.

### Restore Nextcloud, Immich, or Paperless

Use the same pattern and map the namespace to a temporary restore namespace first:

```bash
velero restore create immich-restore-test \
  --from-backup <backup-name> \
  --namespace-mappings immich:immich-restore-test
```

```bash
velero restore create paperless-restore-test \
  --from-backup <backup-name> \
  --namespace-mappings paperless-ngx:paperless-restore-test
```

Once the test restore looks good, re-run the restore into the production namespace only when you are ready to replace the live data.

## Capacity Monitoring

Check Pi space regularly:

```bash
ssh hannes@192.168.178.2 'df -h /srv/minio/velero 2>/dev/null || df -h /srv/minio 2>/dev/null || df -h'
```

Also watch the size of the backup repository and the Velero logs. If the Pi starts filling up, shorten the retention window before backups begin to fail.

## Credential Rotation

If you rotate MinIO or Velero credentials:

1. Update the Pi MinIO root credentials.
2. Update the encrypted Kubernetes secrets in `infrastructure/configs/`.
3. Reconcile Flux and confirm that `velero` becomes `Available` again.

Do not commit plaintext secrets. Keep all real values in SOPS-encrypted manifests or on the Pi itself.
