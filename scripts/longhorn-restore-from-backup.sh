#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <backup-url> <restore-volume-name> <storage-class>" >&2
  echo "example: $0 s3://longhorn-backups@minio-internal.internal:9000/longhorn?backup=backup-... restored-nextcloud longhorn-nextcloud-fast" >&2
  exit 1
fi

backup_url="$1"
volume_name="$2"
storage_class="$3"
restore_class="restore-${volume_name}"

kubectl get storageclass "$storage_class" >/dev/null

kubectl apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ${restore_class}
  annotations:
    storage.passercluster.io/temporary-restore-class: "true"
    storage.passercluster.io/source-class: "${storage_class}"
provisioner: driver.longhorn.io
allowVolumeExpansion: true
parameters:
  numberOfReplicas: "1"
  dataLocality: best-effort
  fromBackup: "${backup_url}"
reclaimPolicy: Retain
volumeBindingMode: Immediate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${volume_name}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: ${restore_class}
  resources:
    requests:
      storage: 10Gi
EOF

echo "Created restore PVC ${volume_name} with temporary StorageClass ${restore_class}."
echo "Resize the PVC after Longhorn imports the backup if the original volume is larger than 10Gi."
