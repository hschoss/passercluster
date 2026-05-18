#!/usr/bin/env bash
set -euo pipefail

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

check_disk() {
  local node_ip="$1"
  local disk="$2"
  local purpose="$3"

  echo "==> ${node_ip}: checking ${disk} (${purpose})"
  local disks
  if ! disks="$(talosctl --nodes "$node_ip" get disks 2>&1)"; then
    echo "ERROR: unable to query Talos disks on ${node_ip}" >&2
    echo "$disks" >&2
    exit 1
  fi

  if ! grep -qE "(^|[[:space:]/])${disk#/dev/}([[:space:]]|$)" <<<"$disks"; then
    echo "ERROR: ${disk} not reported by Talos on ${node_ip}" >&2
    echo "$disks" >&2
    exit 1
  fi

  local partitions
  partitions="$(talosctl --nodes "$node_ip" get discoveredvolumes 2>/dev/null | grep -E "${disk#/dev/}[0-9p]+" || true)"
  if [[ -n "$partitions" ]]; then
    echo "WARN: ${disk} has discovered partitions on ${node_ip}; verify no existing data before applying Longhorn patches."
    echo "$partitions"
  fi
}

require talosctl
require grep

check_disk 192.168.178.200 /dev/nvme0n1 "Talos OS only; no Longhorn"
check_disk 192.168.178.201 /dev/nvme0n1 "Talos OS plus Longhorn performance-secondary partition"
check_disk 192.168.178.202 /dev/sdb "Talos OS disk"
check_disk 192.168.178.202 /dev/nvme0n1 "Longhorn performance disk"
check_disk 192.168.178.203 /dev/sdh "Talos OS disk"
check_disk 192.168.178.203 /dev/sdf "Longhorn capacity disk"
check_disk 192.168.178.203 /dev/sdg "Longhorn capacity disk"
check_disk 192.168.178.203 /dev/sdi "Longhorn backup disk"

echo "Disk inventory check completed. Treat WARN lines as blockers until manually verified."
