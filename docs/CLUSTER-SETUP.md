# Cluster Setup

This is the bootstrap and recovery runbook for the production Talos and Flux cluster.

## Boot Order

Do not skip the order.

1. Talos control plane healthy
2. Kubernetes API reachable
3. Flux controllers healthy
4. `infra-controllers` reconciled
5. `infra-configs` reconciled
6. `apps` reconciled
7. Velero and MinIO healthy

## First Checks

```bash
cd ~/gh/passercluster/talos
talosctl health --nodes 192.168.178.200 --endpoints 192.168.178.200 --talosconfig ./talosconfig
kubectl get nodes -o wide
flux get kustomizations -A
flux get helmreleases -A
```

## Canonical Flux Entry Points

- `clusters/production/infrastructure.yaml`
- `clusters/production/apps.yaml`
- `infrastructure/controllers/production/kustomization.yaml`
- `infrastructure/configs/production/kustomization.yaml`
- `apps/production/kustomization.yaml`

## Recovery Notes

- Use Talos rather than SSH for node recovery.
- Refresh kubeconfig from `talosctl kubeconfig` if the API endpoint changes.
- Reconcile infrastructure before apps whenever you are restoring from an outage.
