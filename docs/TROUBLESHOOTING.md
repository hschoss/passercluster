# Troubleshooting

Failure symptoms first, then the fix. Every command assumes `KUBECONFIG` and `TALOSCONFIG` are exported (see `OPERATIONS.md`).

## App URL times out / connection refused

Order to check:

```bash
# 1. gateway reachable?
kubectl -n envoy-gateway-system get svc | grep 240
# 2. HTTPRoute accepted?
kubectl -n <app-ns> get httproute
kubectl -n <app-ns> describe httproute <name>            # look for "Accepted=True"
# 3. Service actually has endpoints?
kubectl -n <app-ns> get endpoints
# 4. Pod running?
kubectl -n <app-ns> get pods
```

If DNS is the culprit (`nslookup <host>.passer.lan` fails but `--resolve` works):
- Pi-hole must forward `passer.lan` to CoreDNS at `192.168.178.241`.
- `kubectl -n homelab-dns logs deploy/coredns --tail=30`
- `kubectl -n external-dns logs deploy/external-dns --tail=30`

## Pods stuck in `ContainerCreating` after a worker/CP reboot

Almost always the Flannel `cni0` bridge holding a stale pod-CIDR. `describe pod` shows:

```
failed to set bridge addr: "cni0" already has an IP address different from 10.244.X.1/24
```

Fix: kexec-reboot the affected worker, wait until Ready.

```bash
talosctl -n 192.168.178.201 reboot
kubectl get node talos-m2p-286 -w
```

Do them one at a time, not in parallel.

## Longhorn volume shows `replica scheduling failed`

Only nodes tagged for the volume's storage class can host its replicas. Check:

```bash
kubectl -n longhorn-system get nodes.longhorn.io <node> -o jsonpath='{.spec.tags}'
kubectl get sc <storage-class> -o yaml | grep -A3 parameters
```

Example: `longhorn-nvme-201` requires node **and** disk tagged `nvme-201`. If the tag is missing from the node CR, add it via the Longhorn UI (`https://longhorn.passer.lan`) or `kubectl edit nodes.longhorn.io <name>`.

If the volume was placed on the wrong node because the workload pod scheduled there first, add a `nodeSelector` to the workload (see `apps/base/immich/postgres.yaml` for a CNPG example pinning to `talos-m2p-286`).

## Flux Kustomization stuck in `Reconciling`

```bash
flux -n flux-system get kustomizations
flux -n flux-system describe kustomization <name>
```

Common causes:
- `sops-age` secret missing → `kubectl -n flux-system create secret generic sops-age --from-file=age.agekey=$HOME/.config/sops/age/keys.txt`
- New CRD applied in the same reconcile as a CR using it → reconcile again after a few seconds.
- `dependsOn` upstream is not Ready.

## `GitRepository` failing to pull

The tracked `clusters/production/flux-system/gotk-sync.yaml` uses `https://github.com/hschoss/passercluster.git` (public, anonymous). If someone switched it to SSH:

```bash
kubectl -n flux-system patch gitrepository flux-system --type=json \
  -p '[{"op":"remove","path":"/spec/secretRef"},
       {"op":"replace","path":"/spec/url","value":"https://github.com/hschoss/passercluster.git"}]'
```

## Immich starts but `permission denied to create extension "vector"`

CNPG's `postInitSQL` runs on the `postgres` DB. Extensions the app needs must be in `postInitApplicationSQL` (the app DB). Fix in `apps/base/immich/postgres.yaml`, then either recreate the DB or install the extensions manually as `postgres`:

```bash
kubectl -n immich exec immich-postgres-1 -- psql -U postgres -d immich \
  -c "CREATE EXTENSION IF NOT EXISTS vector;
      CREATE EXTENSION IF NOT EXISTS vchord CASCADE;
      CREATE EXTENSION IF NOT EXISTS cube CASCADE;
      CREATE EXTENSION IF NOT EXISTS earthdistance CASCADE;"
kubectl -n immich rollout restart deploy/immich-server
```

## Ghost node in `kubectl get nodes`

Old hostname of a re-installed CP or worker sticks around. Confirm the ghost is not in Talos discovery (`talosctl get members`), then delete it:

```bash
kubectl delete node <ghost-name>
```

DaemonSet pods with `nodeAffinity` pointing at the ghost need one force-delete each:

```bash
kubectl -n longhorn-system delete pod <pending-daemon-pod> --force --grace-period=0
```

## Control-plane hangs (`stopAllPods`, load spike, `/var` unresponsive)

Symptoms and fix in `docs/CONTROL-PLANE-FIX.md`. Short version:

```bash
talosctl -n 192.168.178.200 reboot --mode force
```

If the node comes back in **Maintenance** with STATE/EPHEMERAL partitions missing (has happened twice), re-apply the last known `talos/controlplane.yaml`:

```bash
talosctl apply-config --insecure -n 192.168.178.200 --file talos/controlplane.yaml
talosctl -n 192.168.178.200 bootstrap
```

The Kubernetes CA is embedded in that file, so `~/.kube/config` keeps working.

## Rotating a SOPS-encrypted secret

```bash
sops apps/base/<app>/<file>.secret.yaml         # edit in-place, saves re-encrypted
flux reconcile kustomization apps -n flux-system
```

If a plaintext secret ever gets committed:
1. Rotate the credential (change password, revoke token, etc.).
2. Re-encrypt with `sops -e -i`.
3. Purge from history (`git filter-repo --invert-paths --path <file>`) and force-push.
