# passercluster — project brief

This file is the full-picture reference for anyone (human or AI) starting
work in this repo. It captures cluster identity, invariants, conventions,
common ops recipes and the failure modes that have actually hit this
system. `docs/` contains the deeper runbooks that this file points at.

> **Nothing here is a substitute for reading the code.** Manifests move.
> When something in this file disagrees with `apps/base/`, `clusters/production/`
> or `infrastructure/`, the manifests are the truth.

---

## 1. What this repo controls

A single-cluster homelab, Talos + Flux, all state in this repo.

**Nodes (fixed by DHCP reservation):**

| IP              | Hostname        | Role          | Longhorn tags               |
|-----------------|-----------------|---------------|-----------------------------|
| 192.168.178.200 | `talos-krw-er8` | control-plane | none (no data disks)        |
| 192.168.178.201 | `talos-m2p-286` | worker        | `nvme`, `nvme-201`          |
| 192.168.178.202 | `talos-7tm-1kh` | worker        | `nvme`, `nvme-202`, `ssd`   |
| 192.168.178.203 | `talos-8bp-pih` | worker        | `capacity`, `backup`, `hdd`, `media` |

**Reserved IPs on the LAN:**

| IP              | Owner                                                    |
|-----------------|----------------------------------------------------------|
| 192.168.178.240 | Envoy Gateway (MetalLB LoadBalancer, `lan-pool`)         |
| 192.168.178.241 | CoreDNS (`homelab-dns` namespace, MetalLB)               |
| 192.168.178.2   | `passer` (Raspberry Pi, MinIO for Velero backups)        |

**Hostnames on the LAN — `*.passer.lan`:**

DNS resolution: Pi-hole forwards every `*.passer.lan` (including the
apex) to CoreDNS at `.241`. CoreDNS answers with `.240` (the Gateway).
TLS is one self-signed wildcard: `passer-lan-tls` covers `passer.lan` +
`*.passer.lan`. Browsers warn until you import
`secrets/passer-lan.crt` into your trust store.

---

## 2. Repository layout

```
CLAUDE.md                  # this file
README.md                  # short user-facing overview
.sops.yaml                 # SOPS creation rules — every *.secret.yaml is age-encrypted
.gitignore                 # keeps talos/, secrets/, .claude/ out of git

apps/
  base/          # canonical per-app manifests (namespace, release, secrets, HTTPRoute)
  production/    # overlays: values patches, HTTPRoute host overrides, adds resources
  staging/, e2e/ # non-production overlays (rarely touched)

clusters/
  production/
    apps.yaml                  # Flux Kustomization: apps → apps/production
    infrastructure.yaml        # Flux Kustomizations: infra-controllers, infra-configs, infra-velero, infra-velero-schedules
    artifacts.yaml             # ArtifactGenerator that carves the monorepo into apps/ + infrastructure/ artifacts
    flux-system/               # bootstrap manifests for Flux itself
  staging/, e2e/               # non-prod

infrastructure/
  controllers/       # HelmReleases + HelmRepositories: Envoy Gateway, cert-manager, CNPG, external-dns, CoreDNS, Longhorn, MetalLB
  configs/           # cluster-wide config: Gateway CR, MetalLB IP pool, Longhorn node labels/disks, StorageClasses, ClusterIssuers, Velero config, TLS-replication scripts
  velero/            # Velero HelmRelease + credentials
  velero-schedules/  # backup schedules

scripts/           # bash helpers (see §8)
docs/              # runbooks; docs/README.md is the map
talos/             # machine configs + kubeconfig/talosconfig (GITIGNORED)
secrets/           # locally generated TLS (GITIGNORED)
```

---

## 3. Flux control chain

```
GitRepository flux-system
        │
        └── ArtifactGenerator (clusters/production/artifacts.yaml)
                ├── ExternalArtifact/infrastructure
                └── ExternalArtifact/apps

Kustomization flux-system
        │
        ├── Kustomization infra-controllers      # infrastructure/controllers/production
        │        │
        │        └── Kustomization infra-configs # infrastructure/configs/production
        │                 │
        │                 ├── Kustomization apps # apps/production
        │                 │
        │                 └── Kustomization infra-velero
        │                          │
        │                          └── Kustomization infra-velero-schedules
```

Everything is chained via `dependsOn`. A failure in `infra-configs`
stops **every** downstream kustomization, so `apps` will never roll
out — this has happened when stale node references in
`infrastructure/configs/longhorn-node-labels.yaml` created ghost
`Node.longhorn.io` CRs and Longhorn's validating webhook refused
further disk changes. See §12.

**All Kustomizations that touch a `*.secret.yaml` set `spec.decryption.provider: sops`** with `secretRef: sops-age`. That Secret is created out-of-band from `~/.config/sops/age/keys.txt`. If missing, every downstream kustomization goes `NotReady` with a decryption error.

Reconcile order, fast → slow:

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infra-controllers -n flux-system
flux reconcile kustomization infra-configs -n flux-system
flux reconcile kustomization apps -n flux-system
```

---

## 4. Apps inventory

| App             | Namespace       | Host(s)                                     | Chart / image                                   | Storage                          |
|-----------------|-----------------|---------------------------------------------|-------------------------------------------------|----------------------------------|
| passer-home     | `passer-home`   | `passer.lan`                                | `nginxinc/nginx-unprivileged` (static)          | ConfigMaps                       |
| Authentik       | `authentik`     | `auth.passer.lan`, `authentik.passer.lan`   | `goauthentik.io/charts/authentik`               | CNPG cluster `authentik-postgres`|
| Nextcloud       | `nextcloud`     | `nextcloud.passer.lan`                      | `nextcloud/nextcloud`                           | MariaDB subchart + Longhorn PVC  |
| Immich          | `immich`        | `immich.passer.lan`                         | `ghcr.io/immich-app/immich-charts/immich` OCI   | CNPG cluster `immich-postgres`, valkey, media on `talos-7tm-1kh` |
| Jellyfin        | `jellyfin`      | `jellyfin.passer.lan`                       | `jellyfin/jellyfin`                             | Config on `longhorn`, media on `longhorn-jellyfin` (`talos-8bp-pih`) |
| Paperless-ngx   | `paperless-ngx` | `paperless.passer.lan`                      | `paperless-ngx` (gabe565 chart)                 | Postgres + Redis subcharts, Longhorn PVCs |
| Vaultwarden     | `vaultwarden`   | `vaultwarden.passer.lan`                    | `guerzon/vaultwarden`                           | Longhorn PVC                     |
| Podinfo         | `podinfo`       | `podinfo.passer.lan`                        | `stefanprodan/podinfo`                          | none                             |
| Finance (Findash)| `finance`      | `finance.passer.lan`                        | placeholder nginx today; `ghcr.io/hschoss/findash` planned | CNPG cluster (planned)   |
| Longhorn UI     | `longhorn-system`| `longhorn.passer.lan`                      | Longhorn chart                                  | n/a                              |

Every app follows the same convention (see §7). The passer.lan landing
page and its docs directory are generated from `apps/base/passer-home/`
plus the files in `docs/` — a `configMapGenerator` in that kustomization
pulls `../../../docs/*.md` in and hashes the ConfigMap name, so a doc
change rolls the pod.

---

## 5. DNS + TLS

```
LAN client
   │ resolve  <name>.passer.lan
   ▼
Pi-hole (default LAN DNS)
   │ forward *.passer.lan
   ▼
CoreDNS   at 192.168.178.241   (homelab-dns namespace, MetalLB IP)
   │ static A records or external-dns entries → 192.168.178.240
   ▼
Envoy Gateway   at 192.168.178.240   (envoy-gateway-system, MetalLB IP)
   │ HTTPRoute match on Host header
   ▼
Backend Service in the app's namespace
```

**Cert chain:** self-signed, no ACME. `scripts/generate-passer-lan-cert.sh`
mints a CA + wildcard leaf; `scripts/apply-passer-lan-tls-secret.sh`
replicates the leaf Secret (`passer-lan-tls`) into every namespace that
needs it, plus the `envoy-gateway-system` namespace where the Gateway
listener references it.

**SANs on `passer-lan-tls`:** `passer.lan`, `*.passer.lan`. The apex is
covered — this is why `passer.lan` works without a second cert.

**Adding a new hostname:** just point a new HTTPRoute at the Envoy
Gateway with the desired hostname. external-dns picks up the hostname
from the HTTPRoute and writes it into CoreDNS, and the Gateway's TLS
listener already serves the wildcard cert.

---

## 6. Secrets (SOPS + age)

- Age recipient: `age15ry0az96h329q6hwvzewyl0re9gl554n73megqyk276kkrr7pvuqpyp4y8` (public, in `.sops.yaml`).
- Private key: `~/.config/sops/age/keys.txt` (symlinked from `~/.dotfiles-local`).
- Every file whose name matches `*.secret.yaml` gets encrypted at `stringData`/`data` (see `.sops.yaml`).
- The cluster decrypts with a `flux-system/sops-age` Secret, created out-of-band from the same age key.

Commands:

```bash
sops apps/base/<app>/<file>.secret.yaml            # decrypt → editor → re-encrypt on save
sops --decrypt apps/base/<app>/<file>.secret.yaml  # print plaintext (be careful)
sops --encrypt --in-place path/to/new.secret.yaml  # first-time encrypt
```

**Do not** commit a `*.secret.yaml` that is not encrypted — every
downstream Kustomization will refuse to apply until it is fixed. A
quick guard before push:

```bash
grep -L 'ENC\[' apps/**/*.secret.yaml infrastructure/**/*.secret.yaml
# anything printed here is still plaintext
```

---

## 7. Conventions

### App layout under `apps/base/<app>/`

```
namespace.yaml              # kind: Namespace, name: <app>
repository.yaml             # HelmRepository or OCIRepository
release.yaml                # HelmRelease with base values
httproute.yaml              # HTTPRoute bound to the Envoy Gateway on <app>.passer.lan
<app>-*.secret.yaml         # SOPS-encrypted secrets (DB creds, OIDC secrets, admin passwords)
kustomization.yaml          # ties them together
```

Environment-specific patches go into `apps/production/<app>-values.yaml`
plus (occasionally) `apps/production/<app>-httproute.yaml`, both listed
as `patches:` in `apps/production/kustomization.yaml`.

### HTTPRoute template

Every app-side HTTPRoute references the Gateway with both listeners:

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app>
  namespace: <app>
spec:
  parentRefs:
    - name: envoy
      namespace: envoy-gateway-system
      sectionName: http
    - name: envoy
      namespace: envoy-gateway-system
      sectionName: https
  hostnames:
    - <app>.passer.lan
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - name: <service>
          port: <port>
```

Charts that expose a `route:` block (Authentik, some bjw-s ones) can
declare the HTTPRoute themselves via chart values — see
`apps/production/authentik-values.yaml`.

### Storage classes

Longhorn StorageClasses are pinned to specific worker nodes via tags:

| StorageClass              | Backing tag(s)         | Where data actually lives                |
|---------------------------|------------------------|------------------------------------------|
| `longhorn`                | any                    | anywhere Longhorn scheduling allows      |
| `longhorn-nvme-201`       | `nvme-201`             | `talos-m2p-286` only                     |
| `longhorn-nvme-202`       | `nvme-202`             | `talos-7tm-1kh` only                     |
| `longhorn-nextcloud-fast` | `nvme-202`             | Nextcloud config / MariaDB               |
| `longhorn-immich-fast`    | `nvme-202`, `ssd`      | Immich library, Paperless media          |
| `longhorn-jellyfin`       | `capacity`, `media`    | `talos-8bp-pih` HDDs                     |

Full definitions in `infrastructure/configs/longhorn-storage-classes.yaml`.
**When you add a StorageClass, also add the matching tag to the target
Node.longhorn.io CR** in `infrastructure/configs/longhorn-node-labels.yaml`,
otherwise `replica scheduling failed`.

### Node pinning

For workloads that must live on a specific node (Immich media on
`talos-7tm-1kh`, MariaDB on the same, Findash postgres wherever
CNPG lands), add `nodeSelector: { kubernetes.io/hostname: <name> }`
to the podSpec or (for HelmReleases) to `defaultPodOptions.nodeSelector`.

### Secret naming

- Cluster-owned credentials: `<app>-credentials` (admin logins).
- DB creds: `<app>-db`.
- OIDC client creds: `<app>-oidc`.
- Blueprint / bootstrap files: `<app>-blueprints`, `<app>-bootstrap`.

---

## 8. Adding a new app (recipe)

1. Pick a namespace name = the app name.
2. Create `apps/base/<app>/` with the six files listed in §7.
3. If the app needs a DB, use CNPG:
   ```yaml
   apiVersion: postgresql.cnpg.io/v1
   kind: Cluster
   metadata: { name: <app>-postgres, namespace: <app> }
   spec:
     instances: 1
     bootstrap:
       initdb: { database: <app>, owner: <app>, secret: { name: <app>-db } }
     storage: { size: 5Gi, storageClass: longhorn-nvme-202 }
   ```
4. If the app talks OIDC, add a Provider + Application entry to
   `apps/base/authentik/authentik-blueprints.secret.yaml` (SOPS-encrypted)
   and a matching `<app>-oidc` Secret in the app namespace. Wiring
   pattern: see `docs/AUTHENTIK-SSO.md`.
5. List the new app in `apps/production/kustomization.yaml` under
   `resources:`. Add any patches to `apps/production/<app>-values.yaml`
   and reference them in the same file's `patches:` list.
6. Commit, push, `flux reconcile kustomization apps -n flux-system`.

Look at `apps/base/passer-home/` for a hand-written non-Helm app,
`apps/base/finance/` for the placeholder + planned CNPG pattern,
`apps/base/paperless-ngx/` for HelmRelease + `valuesFrom` injecting
secrets into env vars.

---

## 9. Useful scripts (`scripts/`)

| Script                                | What it does                                                              |
|---------------------------------------|---------------------------------------------------------------------------|
| `generate-passer-lan-cert.sh`         | Regenerate the self-signed CA + wildcard leaf under `secrets/`            |
| `apply-passer-lan-tls-secret.sh`      | Replicate `passer-lan-tls` into every app namespace that needs it         |
| `authentik-bootstrap.sh`              | Reconcile Authentik, wait ready, optionally start the first-run port-forward on :9000 |
| `longhorn-health-check.sh`            | Print a compact status of Longhorn nodes/disks/volumes                    |
| `longhorn-validate-disks.sh`          | Confirm every declared disk exists and is schedulable                     |
| `longhorn-restore-from-backup.sh`     | Guided restore of a Longhorn PVC from a Velero snapshot                   |
| `validate.sh`                         | Client-side manifest linting; run before `git push`                       |

---

## 10. Common failure modes → fix

Ordered by how often they hit.

### DNS returns the right IP, HTTPS returns 404

The HTTPRoute isn't bound. `kubectl describe httproute -n <ns> <name>`
— look for `Accepted=False` or `ResolvedRefs=False`. Usually a typo
in `parentRefs.name` or a `backendRefs.name` pointing at a Service
that doesn't exist yet.

### Pod stuck in `ContainerCreating` after a worker reboot

Flannel/CNI holding a stale bridge. Reboot the worker via
`talosctl -n <ip> reboot`, one at a time.

### Longhorn volume `replica scheduling failed`

Node tag mismatch. `kubectl -n longhorn-system get nodes.longhorn.io <node> -o yaml`
and compare tags against the StorageClass's `parameters.diskSelector`.
Fix by editing the Longhorn Node in the UI or in
`infrastructure/configs/longhorn-node-labels.yaml`.

### Flux kustomization `NotReady` with `admission webhook "validator.longhorn.io" denied`

Longhorn refuses to apply the change because a disk is mid-sync, a
node CR is stale, or a disk is being removed while replicas still
sit on it. Recovery:

- Ghost node: rename the entry in
  `infrastructure/configs/longhorn-node-labels.yaml`, delete the CR
  (`kubectl -n longhorn-system delete node.longhorn.io <name>` and
  `kubectl delete node <name>`).
- Blocked disk removal: open the Longhorn UI, node → disk → "Request
  Eviction", wait until replicas are gone, then apply.

### CNPG `permission denied to create extension "vector"`

`postInitSQL` runs against the `postgres` DB. Extensions the app
consumes must go in `postInitApplicationSQL`. Fix the manifest
(`apps/base/immich/postgres.yaml` has the pattern), then either drop
and re-create the DB or run the extension `CREATE`s manually as
`postgres` (see `docs/TROUBLESHOOTING.md`).

### Every `HelmRelease` says decryption failed

The `flux-system/sops-age` Secret is missing or wrong. Recreate:

```bash
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=$HOME/.config/sops/age/keys.txt
flux reconcile kustomization flux-system -n flux-system
```

### `GitRepository flux-system` isn't pulling

`kubectl -n flux-system describe gitrepository flux-system` — usually
the URL got flipped to SSH with a missing deploy key. Force back to
HTTPS anonymous:

```bash
kubectl -n flux-system patch gitrepository flux-system --type=json \
  -p '[{"op":"remove","path":"/spec/secretRef"},
       {"op":"replace","path":"/spec/url","value":"https://github.com/hschoss/passercluster.git"}]'
```

---

## 11. After a power outage or full rebuild

1. Power the cluster on. Talos boots automatically; give it ~2 min.
2. `talosctl health --nodes 192.168.178.200 --endpoints 192.168.178.200`
   confirms the control plane is up. If it isn't, see
   `docs/CONTROL-PLANE-FIX.md`.
3. `kubectl get nodes` — all four `Ready`.
4. If nodes were reinstalled with new hostnames, update
   `infrastructure/configs/longhorn-node-labels.yaml` **and**
   `infrastructure/configs/production/longhorn-node-labels.yaml`
   before Flux applies anything. Old hostnames become ghost Longhorn
   Nodes and permanently block infra-configs. See §10.
5. `flux -n flux-system resume kustomization flux-system` if it was
   suspended.
6. Watch: `flux get kustomizations -A -w` until all `Ready=True`.
7. Longhorn volumes reattach on their own; watch
   `kubectl -n longhorn-system get volumes` — expect all `attached`
   and `healthy` within a few minutes.
8. Velero backups: `kubectl -n velero get backup`. If the last
   schedule fired during the outage, it will retry on the next tick.

---

## 12. Known quirks and open issues

### Longhorn admission webhook is picky

Any leftover Longhorn CR from a previous cluster generation
(node, disk, volume) causes `admission webhook validator.longhorn.io denied`
on every subsequent apply of `infrastructure/configs/`, which cascades
into `apps` never getting reconciled. Two real occurrences so far:

- **Ghost node `talos-ja7-1cq`** — old control-plane hostname baked
  into `longhorn-node-labels.yaml`. Fixed in commit `20afd3e` by
  renaming to `talos-krw-er8`.
- **Ghost disk `default-disk-088400000000` on `talos-8bp-pih`** —
  Longhorn refused to delete because replicas / backing images still
  sat on it. Recovery is a manual eviction in the Longhorn UI, then
  the manifest change goes through.

**When Flux says infra-configs isn't ready, this is the first thing
to check.**

### Authentik has no dashboard bootstrap admin password stored

The chart generates a random `akadmin` password on first install and
puts it in the server pod's logs. `scripts/authentik-bootstrap.sh`
sets up a port-forward but does not retrieve the password. Either
grep the logs, or issue a password reset via CLI:

```bash
kubectl -n authentik exec deploy/authentik-worker -- ak shell -c \
  "from authentik.core.models import User; u=User.objects.get(username='akadmin'); u.set_password('CHOOSE-A-NEW-ONE'); u.save()"
```

### Vaultwarden does not do SSO

Upstream does not implement OIDC or SAML — that is a Bitwarden
Enterprise feature. If SSO in front of Vaultwarden matters, either
switch to the `timshel/vaultwarden` fork or accept that the web UI
alone can be proxy-protected (forward-auth via an Authentik outpost)
while every mobile / desktop / browser-extension client would break.

### Immich OAuth is admin-UI-only

Wiring OAuth via `IMMICH_CONFIG_FILE` resets every other admin
setting to defaults, which is worse than a one-time UI paste. So the
repo pre-creates the OIDC client in Authentik (via the blueprint)
and stores the credentials in `immich/immich-oidc`, but the final
paste happens once in `Administration → Settings → Authentication → OAuth`.
See `docs/AUTHENTIK-SSO.md`.

### Jellyfin needs the SSO plugin installed manually

No native OIDC. Add
`https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json`
as a plugin repository in the Jellyfin dashboard, install SSO-Auth,
paste the pre-created client info from the Authentik blueprint.

### Findash image isn't built yet

`finance.passer.lan` currently serves a placeholder from
`apps/base/finance/placeholder-deployment.yaml`. The real
deployment (CNPG + Deployment + migration Job) is written out in
`apps/base/finance/findash.yaml` but not listed in the local
`kustomization.yaml`. Runbook to flip it: `docs/FINDASH-DEPLOY.md`.

### Direct `kubectl apply` in AI sessions is denied by auto-mode

If you use Claude Code in auto-mode inside this repo, three classes
of action are pre-denied by its classifier:

- Editing Longhorn `Node.longhorn.io` CRs (`Modify Shared Resources`).
- Writing decrypted `*.secret.yaml` content back into the cluster
  via `sops --decrypt | kubectl apply` (`Secret-Store Writes`).
- Structural changes that route around either of the above
  (`Auto-Mode Bypass`) — e.g. dropping `dependsOn: infra-configs`
  from `clusters/production/apps.yaml`.

So AI sessions can commit changes but can't manually activate them
in the cluster when Flux is blocked. The classifier can be relaxed
per-command in `~/.claude/settings.json`.

---

## 13. Where to look next

| I want to …                                     | Read this                        |
|-------------------------------------------------|----------------------------------|
| Do a daily health check                         | `docs/OPERATIONS.md`             |
| Debug a broken URL                              | `docs/TROUBLESHOOTING.md`        |
| Understand the routing / DNS / TLS path         | `docs/INGRESS.md`                |
| Add a new app                                   | `docs/ADDING-APPS.md`            |
| Wire an app up to Authentik SSO                 | `docs/AUTHENTIK-SSO.md`          |
| Bring up Authentik for the first time           | `docs/AUTHENTIK.md`              |
| Recover a downed control plane                  | `docs/CONTROL-PLANE-FIX.md`      |
| Set up Velero from scratch                      | `docs/VELERO-SETUP.md`           |
| Understand what gets backed up                  | `docs/velero-backups.md`         |
| Flip Findash from placeholder to the real image | `docs/FINDASH-DEPLOY.md`         |
| Quick copy-pasteable commands                   | `docs/COMMANDS.md`               |
| See the service → URL → namespace map           | `docs/SERVICES.md`               |
