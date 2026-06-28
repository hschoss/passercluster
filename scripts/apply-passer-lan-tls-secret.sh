#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
secrets_dir="${repo_root}/secrets"
crt_file="${secrets_dir}/passer-lan.crt"
key_file="${secrets_dir}/passer-lan.key"
secret_name="passer-lan-tls"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR - kubectl is not installed" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "ERROR - yq is not installed" >&2
  exit 1
fi

if [[ ! -f "$crt_file" || ! -f "$key_file" ]]; then
  echo "ERROR - Missing TLS material" >&2
  echo "Run scripts/generate-passer-lan-cert.sh first." >&2
  exit 1
fi

discover_namespaces() {
  local -a namespaces=()
  local file namespace

  while IFS= read -r -d '' file; do
    namespace="$(yq e '.metadata.name // ""' "$file")"
    if [[ -n "$namespace" ]]; then
      namespaces+=("$namespace")
    fi
  done < <(find "$repo_root/apps/base" -mindepth 2 -maxdepth 2 -name namespace.yaml -print0)

  while IFS= read -r -d '' file; do
    while IFS= read -r namespace; do
      [[ -n "$namespace" ]] && namespaces+=("$namespace")
    done < <(yq e 'select(.kind == "Ingress" or .kind == "HTTPRoute") | .metadata.namespace // ""' "$file")
  done < <(find "$repo_root/apps" "$repo_root/infrastructure" "$repo_root/clusters" -path '*/.*' -prune -o -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)

  namespaces+=("envoy-gateway-system")

  printf '%s\n' "${namespaces[@]}" | awk 'NF && !seen[$0]++'
}

while IFS= read -r namespace; do
  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "WARN - namespace ${namespace} does not exist yet, skipping"
    continue
  fi

  echo "INFO - Applying ${secret_name} in ${namespace}"
  kubectl create secret tls "$secret_name" --cert="$crt_file" --key="$key_file" --namespace "$namespace" --dry-run=client -o yaml | kubectl apply -f -
done < <(discover_namespaces)
