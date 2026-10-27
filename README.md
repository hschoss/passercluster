# passercluster

Home Kubernetes cluster on 4 Talos nodes, managed with Flux from this repo.

## Nodes

| Node | IP | Role | Notes |
|---|---|---|---|
| passer-cp-01 | 192.168.178.200 | control-plane | single CP; etcd not HA |
| passer-w-01  | 192.168.178.201 | worker        | Longhorn tag `nvme-201` |
| passer-w-02  | 192.168.178.202 | worker        | Longhorn tag `nvme-202` (primary DB + media) |
| passer-w-03  | 192.168.178.203 | worker        | Longhorn tags `capacity` + `backup` (HDD) |

## Services (all `https://*.passer.lan`)

- `nextcloud.passer.lan` – file sync + calendar/contacts
- `immich.passer.lan` – photo library
- `jellyfin.passer.lan` – media streaming
- `paperless.passer.lan` – document archive
- `vaultwarden.passer.lan` – password manager
- `auth.passer.lan` / `authentik.passer.lan` – Authentik SSO (see `docs/AUTHENTIK-SSO.md`)
- `longhorn.passer.lan` – storage dashboard
- `podinfo.passer.lan` – smoke-test app
- `finance.passer.lan` – long-term stock dashboard (Findash, first version placeholder — see `docs/FINDASH-DEPLOY.md`)
- `passer.lan` – minimal landing page linking everything, plus the docs at `/docs/`

Sonnen power controller runs as the `sonnen` app (CNPG + collector + decision-engine); not externally reachable, drives `folding` scaling.

DNS: Pi-hole forwards `*.passer.lan` to CoreDNS at `192.168.178.241`. Gateway IP: `192.168.178.240`.

## Getting started as an operator

1. **Read [`CLAUDE.md`](CLAUDE.md)** – the full project brief: layout, conventions, failure modes, quirks.
2. **Talk to the cluster** – kubeconfig and talosconfig live in `talos/`.
   ```bash
   export KUBECONFIG=$PWD/talos/kubeconfig
   export TALOSCONFIG=$PWD/talos/talosconfig
   kubectl get nodes
   ```
3. **Check the health board** – [`docs/OPERATIONS.md`](docs/OPERATIONS.md).
4. **Something is broken** – [`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md).
5. **Change something** – edit files under `apps/` or `infrastructure/`, commit + push, Flux does the rest. To add a whole new app: [`docs/ADDING-APPS.md`](docs/ADDING-APPS.md).

## Layout

```
apps/
  base/<app>/            # per-app manifests (namespace, helmrelease, secrets, HTTPRoute, …)
  production/            # Kustomize overlay: patches on top of the bases
  staging/, e2e/         # alternate overlays
infrastructure/
  controllers/
    base/                # Helm installs: cert-manager, cnpg, coredns, envoy-gateway, external-dns, longhorn, metallb, velero
    production/          # resources: [../base]
    staging/             # subset (cert-manager, envoy-gateway)
  configs/
    base/                # cluster-wide CRs: ClusterIssuer, Gateway, StorageClasses, Longhorn Node CRs, Velero schedules, …
    production/          # resources: [../base]
    staging/             # subset
clusters/
  production/, staging/, e2e/   # Flux bootstrap + per-env Kustomization fan-out
scripts/                 # Operational helpers (apply-node-labels.sh, TLS replication, Longhorn checks, …)
talos/                   # Machine configs + talosconfig + kubeconfig (gitignored)
secrets/                 # Self-signed passer.lan TLS material (gitignored)
docs/                    # Runbooks
```

## Secrets

- SOPS + age. Public key in `.sops.yaml`, private key at `~/.config/sops/age/keys.txt`.
- Every `*.secret.yaml` under `apps/` and `infrastructure/` is encrypted at rest.
- The cluster decrypts them via a `flux-system/sops-age` Secret (created from the same age key).
- The self-signed TLS for `*.passer.lan` lives in `secrets/` and is applied to every namespace with `scripts/apply-passer-lan-tls-secret.sh`.

## Node labels

Node labels (`storage-tier`, `disk-type`, `storage.passercluster.io/*`) are applied with `scripts/apply-node-labels.sh`, not through GitOps. The Node object is kubelet's — managing it with a Flux Kustomization that prunes caused a ghost-node incident on 2026-10-27.
