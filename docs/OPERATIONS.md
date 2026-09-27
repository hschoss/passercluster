# Operations

Day-to-day commands for running the cluster. Every command assumes:

```bash
cd ~/gh/passercluster
export KUBECONFIG=$PWD/talos/kubeconfig
export TALOSCONFIG=$PWD/talos/talosconfig
```

## Health board

```bash
kubectl get nodes -o wide                       # 4 nodes, all Ready
flux get kustomizations -A                      # all True except flux-system (Suspended is OK, see below)
flux get helmreleases -A                        # every HelmRelease Ready=True
kubectl get gateway -A                          # PROGRAMMED=True, ADDRESS=192.168.178.240
kubectl get httproute -A                        # each service on its passer.lan host
kubectl -n longhorn-system get volumes | head   # attached / healthy
```

If any of these are wrong, jump to `TROUBLESHOOTING.md`.

## Flux top-level Kustomization

The `flux-system` Kustomization is intentionally **suspended** in the running cluster because the on-disk `gotk-sync.yaml` used to point at an SSH URL with a deleted deploy key. After the first push of the cleaned-up repo, resume it:

```bash
flux -n flux-system resume kustomization flux-system
```

From then on, everything reconciles from `main` automatically.

## Reconcile flow (fast → slow)

```bash
flux reconcile source git flux-system -n flux-system            # pull the latest commit
flux reconcile kustomization infra-controllers -n flux-system   # CRDs, controllers
flux reconcile kustomization infra-configs -n flux-system       # Gateway, routes, DNS
flux reconcile kustomization apps -n flux-system                # HelmReleases (apps)
```

Dependencies are wired via `dependsOn`, so reconciling `apps` alone is usually enough after an app-only change.

## Talk to Talos

```bash
talosctl -n 192.168.178.200 health
talosctl -n 192.168.178.200 dashboard
talosctl -n 192.168.178.201 logs kubelet -f          # worker logs
talosctl -n 192.168.178.201 reboot                   # kexec reboot, ~60 s
```

## App URLs

| App | URL | Ready when |
|---|---|---|
| Landing page | https://passer.lan | pod `passer-home` 1/1 |
| Nextcloud | https://nextcloud.passer.lan | pods `nextcloud`, `nextcloud-mariadb-0` are 1/1 |
| Immich | https://immich.passer.lan | pods `immich-server`, `immich-postgres-1`, `immich-valkey`, `immich-machine-learning` all 1/1 |
| Jellyfin | https://jellyfin.passer.lan | pod `jellyfin` 1/1 |
| Paperless | https://paperless.passer.lan | pod `paperless-ngx` 1/1 |
| Vaultwarden | https://vaultwarden.passer.lan | pod `vaultwarden` 1/1 |
| Authentik | https://auth.passer.lan (or https://authentik.passer.lan) | server + worker 1/1 (may take ~5 min first boot) |
| Longhorn | https://longhorn.passer.lan | any longhorn-ui pod 1/1 |
| Podinfo | https://podinfo.passer.lan | any podinfo pod 1/1 |
| Findash | https://finance.passer.lan | pod `finance-placeholder` 1/1 today; `findash` after image flip (see `FINDASH-DEPLOY.md`) |

Quick check from any LAN machine:

```bash
for h in nextcloud immich jellyfin; do
  curl -skI --resolve $h.passer.lan:443:192.168.178.240 https://$h.passer.lan/ | head -1
done
```

## TLS and DNS

- Self-signed cert for `*.passer.lan` sits in `secrets/`. Regenerate with `scripts/generate-passer-lan-cert.sh`, then roll it into every namespace with `scripts/apply-passer-lan-tls-secret.sh`.
- `ExternalDNS` writes A records into CoreDNS at `192.168.178.241`; Pi-hole forwards `*.passer.lan` there.
- Browser cert warning is expected. Import `secrets/passer-lan.crt` into the OS/browser trust store on machines you use daily.

## Storage (Longhorn)

- Storage classes are per-node: `longhorn-nvme-201` (talos-m2p-286), `longhorn-nvme-202` (talos-7tm-1kh), and per-workload tiers like `longhorn-nextcloud-fast`, `longhorn-immich-fast`, `longhorn-jellyfin`. Full list: `infrastructure/configs/longhorn-storage-classes.yaml`.
- They pin data to a specific worker via `nodeSelector` + `diskSelector` tags declared in `infrastructure/configs/longhorn-node-labels.yaml`.
- After a worker reboot, watch `kubectl -n longhorn-system get volumes` until every attached volume is `healthy` again.
- Dashboard: `kubectl -n longhorn-system port-forward svc/longhorn-frontend 8080:80` or `https://longhorn.passer.lan`.
- Compact health helper: `scripts/longhorn-health-check.sh`.

## Backups (Velero)

Full docs in `docs/VELERO-SETUP.md` and `docs/velero-backups.md`. Quick check:

```bash
kubectl -n velero get backup
kubectl -n velero get schedule
```

## Change loop

1. Edit under `apps/` (per-app values, HelmRelease) or `infrastructure/`.
2. `git status` – confirm no secrets slipped in (all `*.secret.yaml` should look like `ENC[…]`).
3. Commit, push.
4. `flux reconcile source git flux-system -n flux-system` to pull the new commit immediately, otherwise wait 1 min.
5. Watch: `flux get kustomizations -A -w`.

## Before pushing

- No plaintext credentials outside of `secrets/` (which is gitignored).
- `talos/*.yaml` and `talos/talosconfig` must stay gitignored.
- `sops -d <file>.secret.yaml | head -3` should decode – if it errors, you'll break every downstream Kustomization.
