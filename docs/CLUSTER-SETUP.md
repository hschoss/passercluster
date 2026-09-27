# Cluster Setup

Bootstrap and recovery runbook for the passercluster Talos + Flux stack.
For the running-day view, use `docs/OPERATIONS.md`. For the "what is
this cluster and where does each piece live" picture, read the root
`CLAUDE.md`.

## What you need on your workstation

- `talosctl`, `kubectl`, `flux`, `sops`, `age` — all in PATH.
- The private age key at `~/.config/sops/age/keys.txt`. Public
  recipient is pinned in `.sops.yaml`; without the matching private
  key you cannot decrypt any `*.secret.yaml` file in this repo.
- The `talos/` directory populated with the machine configs and
  credentials (`controlplane.yaml`, `talosconfig`, `kubeconfig`). These
  are gitignored — restore them from your password manager / offline
  backup after a fresh checkout.
- Passer network reachable on the LAN (`192.168.178.0/24`).

## Boot order

Not optional. Each step's readiness gate must pass before the next.

1. **Talos control plane healthy.**
   ```bash
   talosctl -n 192.168.178.200 health --talosconfig talos/talosconfig
   ```
   Expected: `discovered nodes: ["...krw-er8", ...]`, all etcd members ready.
2. **Kubernetes API reachable.**
   ```bash
   export KUBECONFIG=$PWD/talos/kubeconfig
   kubectl get nodes -o wide
   ```
   Expected: all four nodes `Ready`.
3. **Flux controllers healthy.**
   ```bash
   kubectl -n flux-system get pods
   flux -n flux-system get sources git
   ```
   `flux-system` GitRepository must show the latest commit hash.
4. **`sops-age` Secret in place.** If missing:
   ```bash
   kubectl -n flux-system create secret generic sops-age \
     --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
   ```
5. **`infra-controllers` reconciled.**
   ```bash
   flux reconcile kustomization infra-controllers -n flux-system
   flux get kustomization infra-controllers -n flux-system
   ```
   Installs Envoy Gateway, cert-manager, CNPG, external-dns, CoreDNS,
   Longhorn, MetalLB.
6. **`infra-configs` reconciled.**
   ```bash
   flux reconcile kustomization infra-configs -n flux-system
   ```
   Applies the Gateway CR, MetalLB IP pool, Longhorn Node CRs +
   StorageClasses, ClusterIssuers, Velero + MinIO credentials.
7. **`apps` reconciled.**
   ```bash
   flux reconcile kustomization apps -n flux-system
   ```
   Rolls out every HelmRelease under `apps/production/`.
8. **Velero healthy.**
   ```bash
   flux reconcile kustomization infra-velero -n flux-system
   kubectl -n velero get pods
   kubectl -n velero get backup
   ```

## Canonical Flux entry points

| File                                                                       | What it declares                                     |
|----------------------------------------------------------------------------|------------------------------------------------------|
| `clusters/production/flux-system/`                                         | Bootstrap manifests for Flux itself                  |
| `clusters/production/artifacts.yaml`                                       | `ArtifactGenerator` splitting the monorepo into `infrastructure` + `apps` ExternalArtifacts |
| `clusters/production/infrastructure.yaml`                                  | Flux Kustomizations `infra-controllers`, `infra-configs`, `infra-velero`, `infra-velero-schedules` |
| `clusters/production/apps.yaml`                                            | Flux Kustomization `apps` → `apps/production`        |
| `infrastructure/controllers/production/kustomization.yaml`                 | Controllers overlay                                  |
| `infrastructure/configs/production/kustomization.yaml`                     | Configs overlay (Longhorn node labels, StorageClasses, gateway, etc.) |
| `apps/production/kustomization.yaml`                                       | Which apps are enabled + patches per app             |

## Fresh cluster from a wiped `passercluster` checkout

Rare — if the repo has been recloned and there is no `talos/` yet.

1. Restore `talos/controlplane.yaml`, `talos/talosconfig`, `talos/kubeconfig`
   from your offline backup.
2. Follow the boot order above.
3. If the SOPS decryption never succeeds even though `sops-age` is
   present, the age key rotated. Re-encrypt every `*.secret.yaml`
   against the new recipient (update `.sops.yaml` and run
   `sops updatekeys` on each file).

## Rebuilding a single node

If one Talos node was reinstalled and got a new hostname, both files
below must be updated **before** Flux applies anything:

- `infrastructure/configs/longhorn-node-labels.yaml`
- `infrastructure/configs/production/longhorn-node-labels.yaml`

Otherwise the old hostname sticks around as a stale `Node.longhorn.io`
CR and Longhorn's validating webhook rejects every further apply of
`infrastructure/configs/` (`admission webhook "validator.longhorn.io" denied`).
See `docs/TROUBLESHOOTING.md` for the cleanup.

## Recovery notes

- Talos is the front door for node recovery. SSH is not enabled — use
  `talosctl` for logs, reboots, config apply.
- If the API endpoint changes, refresh `talos/kubeconfig` with:
  ```bash
  talosctl kubeconfig -n 192.168.178.200 --talosconfig talos/talosconfig talos/kubeconfig
  ```
- Reconcile infrastructure before apps whenever you are restoring
  from an outage — `apps` depends on `infra-configs`, and skipping
  the order leaves everything half-applied.
