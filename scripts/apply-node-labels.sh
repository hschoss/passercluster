#!/bin/bash
# Apply storage/role labels to the four passercluster nodes.
#
# Why this is a script and not a GitOps-managed `kind: Node` resource:
# the Node object is owned by kubelet. When Flux renders this via a
# Kustomization with `prune: true` and the name changes, Flux deletes
# the real Node object (incident: 2026-10-27). Labels belong to the
# cluster's day-2 side, kept idempotent with `kubectl label --overwrite`.
#
# Idempotent — safe to re-run after every node rename or re-provision.
#
# Usage:
#   KUBECONFIG=~/gh/passercluster/talos/kubeconfig scripts/apply-node-labels.sh

set -euo pipefail

: "${KUBECONFIG:=$HOME/gh/passercluster/talos/kubeconfig}"
export KUBECONFIG

label() {
  local node="$1"; shift
  echo "→ ${node}"
  kubectl label --overwrite node "${node}" "$@"
}

# Node 200 — control plane (passer-cp-01). No data disks.
label passer-cp-01 \
  storage.passercluster.io/longhorn=disabled \
  storage.passercluster.io/node-id=200 \
  node.longhorn.io/create-default-disk=false

# Node 201 — passer-w-01: 1 TB NVMe, performance tier.
label passer-w-01 \
  storage-tier=performance \
  disk-type=nvme \
  storage.passercluster.io/longhorn=enabled \
  storage.passercluster.io/node-id=201 \
  node.longhorn.io/create-default-disk=false

# Node 202 — passer-w-02: 2 TB NVMe + Samsung SATA SSD, performance-primary.
label passer-w-02 \
  storage-tier=performance \
  disk-type=nvme \
  storage.passercluster.io/longhorn=enabled \
  storage.passercluster.io/node-id=202 \
  node.longhorn.io/create-default-disk=false

# Node 203 — passer-w-03: 2x4TB HDD + 500GB HDD + 250GB SATA SSD, capacity.
label passer-w-03 \
  storage-tier=capacity \
  disk-type=hdd \
  storage.passercluster.io/longhorn=enabled \
  storage.passercluster.io/node-id=203 \
  node.longhorn.io/create-default-disk=false

echo "Done."
