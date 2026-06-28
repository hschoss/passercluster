#!/usr/bin/env bash

set -euo pipefail

namespace="authentik"
flux_namespace="flux-system"
kustomization="apps"
local_port="9000"
remote_service="authentik-server"
remote_port="80"
reconcile="true"
start_port_forward="false"

usage() {
  cat <<'EOF'
Usage: scripts/authentik-bootstrap.sh [options]

Reconcile the Authentik GitOps stack, wait for it to become ready, and
print the first-bootstrap port-forward command.

Options:
  --namespace <name>        Authentik namespace (default: authentik)
  --flux-namespace <name>   Flux namespace (default: flux-system)
  --kustomization <name>    Flux kustomization to reconcile (default: apps)
  --local-port <port>       Local bootstrap port (default: 9000)
  --remote-service <name>   Authentik service to port-forward (default: authentik-server)
  --remote-port <port>      Remote service port (default: 80)
  --skip-reconcile          Skip flux reconcile and only wait for readiness
  --port-forward            Start the bootstrap port-forward after readiness
  -h, --help                Show this help text
EOF
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR - missing required command: $1" >&2
    exit 1
  fi
}

wait_for_resource() {
  local kind="$1"
  local name="$2"
  local ns="$3"
  local timeout="${4:-20m}"

  echo "INFO - Waiting for ${kind}/${name} in namespace ${ns}"
  until kubectl -n "$ns" get "${kind}/${name}" >/dev/null 2>&1; do
    sleep 5
  done
  kubectl -n "$ns" wait --for=condition=Ready "${kind}/${name}" --timeout="$timeout"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      namespace="${2:-}"
      shift 2
      ;;
    --flux-namespace)
      flux_namespace="${2:-}"
      shift 2
      ;;
    --kustomization)
      kustomization="${2:-}"
      shift 2
      ;;
    --local-port)
      local_port="${2:-}"
      shift 2
      ;;
    --remote-service)
      remote_service="${2:-}"
      shift 2
      ;;
    --remote-port)
      remote_port="${2:-}"
      shift 2
      ;;
    --skip-reconcile)
      reconcile="false"
      shift
      ;;
    --port-forward)
      start_port_forward="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR - unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

need_cmd kubectl
if [[ "$reconcile" == "true" ]]; then
  need_cmd flux
fi

if [[ "$reconcile" == "true" ]]; then
  echo "INFO - Reconciling Flux kustomization ${kustomization} in ${flux_namespace}"
  flux reconcile kustomization "$kustomization" -n "$flux_namespace" --with-source
fi

wait_for_resource helmrelease authentik "$namespace"
wait_for_resource cluster authentik-postgres "$namespace"

echo "INFO - Authentik is ready"
echo "INFO - First bootstrap URL: http://127.0.0.1:${local_port}"
echo "INFO - Port-forward command: kubectl -n ${namespace} port-forward svc/${remote_service} ${local_port}:${remote_port}"

if [[ "$start_port_forward" == "true" ]]; then
  exec kubectl -n "$namespace" port-forward "svc/${remote_service}" "${local_port}:${remote_port}"
fi
