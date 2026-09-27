# passercluster

Home Kubernetes cluster on 4 Talos nodes, managed with Flux from this repo.

## Nodes

| Node | IP | Role | Notes |
|---|---|---|---|
| talos-krw-er8 | 192.168.178.200 | control-plane | fresh CA/etcd since 2026-09-27 |
| talos-m2p-286 | 192.168.178.201 | worker | Longhorn tag `nvme-201` (fast, primary DB) |
| talos-7tm-1kh | 192.168.178.202 | worker | Longhorn tag `nvme-202` (media, big fast disk) |
| talos-8bp-pih | 192.168.178.203 | worker | Longhorn tag `capacity` (HDD, cold storage) |

## Services (all `https://*.passer.lan`)

- `nextcloud.passer.lan` – file sync + calendar/contacts
- `immich.passer.lan` – photo library
- `jellyfin.passer.lan` – media streaming
- `paperless.passer.lan` – document archive
- `vaultwarden.passer.lan` – password manager
- `auth.passer.lan` / `authentik.passer.lan` – Authentik SSO (see `docs/AUTHENTIK-SSO.md`)
- `longhorn.passer.lan` – storage dashboard
- `podinfo.passer.lan` – smoke-test app

DNS: Pi-hole forwards `*.passer.lan` to CoreDNS at `192.168.178.241`. Gateway IP: `192.168.178.240`.

## Getting started as an operator

1. **Talk to the cluster** – kubeconfig and talosconfig live in `talos/`.
   ```bash
   export KUBECONFIG=$PWD/talos/kubeconfig
   export TALOSCONFIG=$PWD/talos/talosconfig
   kubectl get nodes
   ```
2. **Check the health board** – `docs/OPERATIONS.md`.
3. **Something is broken** – `docs/TROUBLESHOOTING.md`.
4. **Change something** – edit files under `apps/` or `infrastructure/`, commit + push, Flux does the rest.

## Layout

```
apps/            # HelmReleases + values per application
clusters/        # Flux entry points (GitRepository + top-level Kustomizations)
infrastructure/  # Controllers (Envoy, cert-manager, MetalLB, Longhorn, …) + configs
talos/           # Machine config & credentials (gitignored)
secrets/         # Self-signed passer.lan TLS material (gitignored)
scripts/         # Small helpers (TLS apply, Longhorn checks, Velero restore)
docs/            # Runbooks
```

## Secrets

- SOPS + age. Public key in `.sops.yaml`, private key at `~/.config/sops/age/keys.txt`.
- Every `*.secret.yaml` under `apps/` and `infrastructure/` is encrypted at rest.
- The cluster decrypts them via a `flux-system/sops-age` Secret (created from the same age key).
- The self-signed TLS for `*.passer.lan` lives in `secrets/` and is applied to every namespace with `scripts/apply-passer-lan-tls-secret.sh`.
