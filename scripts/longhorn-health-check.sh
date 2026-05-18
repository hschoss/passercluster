#!/usr/bin/env bash
set -euo pipefail

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require kubectl

echo "==> Longhorn pods"
kubectl -n longhorn-system get pods -o wide

echo "==> Longhorn nodes"
kubectl -n longhorn-system get nodes.longhorn.io \
  talos-z8c-je7 talos-3nt-pq2 talos-w45-5vh \
  -o custom-columns=NAME:.metadata.name,SCHEDULABLE:.spec.allowScheduling,TAGS:.spec.tags

echo "==> StorageClasses"
kubectl get storageclass \
  longhorn-nextcloud-fast longhorn-immich-fast longhorn-jellyfin longhorn-backup

echo "==> Volumes and robustness"
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,NODE:.status.currentNodeID,SIZE:.spec.size

echo "==> Recurring jobs"
kubectl -n longhorn-system get recurringjobs.longhorn.io

echo "==> Backup target settings"
kubectl -n longhorn-system get backuptargets.longhorn.io default -o yaml
