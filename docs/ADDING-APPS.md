# Adding a new app

Concrete walk-through. Uses `myapp` as the placeholder — replace it
everywhere.

## Prerequisites

- You know the app's Helm chart (or you're deploying a hand-rolled
  Deployment).
- You've picked a hostname: `myapp.passer.lan`.
- If the app needs a database, you know whether Postgres (CNPG),
  MariaDB (subchart, see Nextcloud) or SQLite fits.

## 1. Create the base directory

```bash
mkdir -p apps/base/myapp
```

Six standard files. Copy the pattern from an existing app such as
`apps/base/paperless-ngx/`.

### `namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: myapp
```

### `repository.yaml`
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: myapp
  namespace: myapp
spec:
  interval: 24h
  url: https://charts.example.com
```

Or `OCIRepository` for OCI charts (see `apps/base/immich/oci-repository.yaml`).

### `release.yaml`
```yaml
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: myapp
  namespace: myapp
spec:
  interval: 30m
  chart:
    spec:
      chart: myapp
      version: ">=1.0.0"
      sourceRef:
        kind: HelmRepository
        name: myapp
        namespace: myapp
  install:
    remediation: { retries: 3 }
  upgrade:
    cleanupOnFail: true
    remediation: { strategy: rollback, retries: 3 }
  values:
    persistence:
      enabled: true
      storageClass: longhorn-nvme-202
      size: 5Gi
    ingress:
      enabled: false           # HTTPRoute handles routing, not the chart's Ingress
```

### `httproute.yaml`
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: myapp
  namespace: myapp
spec:
  parentRefs:
    - name: envoy
      namespace: envoy-gateway-system
      sectionName: http
    - name: envoy
      namespace: envoy-gateway-system
      sectionName: https
  hostnames:
    - myapp.passer.lan
  rules:
    - matches:
        - path: { type: PathPrefix, value: / }
      backendRefs:
        - name: myapp
          port: 80
```

### `myapp-db.secret.yaml` (only if the app needs a DB)
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: myapp-db
  namespace: myapp
type: kubernetes.io/basic-auth
stringData:
  username: myapp
  password: <generate with `openssl rand -hex 24`>
```

Then encrypt: `sops --encrypt --in-place apps/base/myapp/myapp-db.secret.yaml`.

### `kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: myapp
resources:
  - namespace.yaml
  - repository.yaml
  - release.yaml
  - httproute.yaml
  - myapp-db.secret.yaml    # only if you added the secret
```

## 2. Wire in a CNPG Postgres (optional)

If the app wants Postgres, prefer CNPG over a chart-bundled Postgres:

```yaml
# apps/base/myapp/postgres.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: myapp-postgres
  namespace: myapp
spec:
  instances: 1
  bootstrap:
    initdb:
      database: myapp
      owner: myapp
      secret: { name: myapp-db }
  storage:
    size: 5Gi
    storageClass: longhorn-nvme-202
  resources:
    requests: { cpu: 50m, memory: 128Mi }
    limits:   { cpu: 500m, memory: 512Mi }
```

Add it to `kustomization.yaml`. The chart's `env` / `values` block
should point at `myapp-postgres-rw.myapp.svc.cluster.local:5432`.

## 3. Environment patches

Overlay-specific tweaks live in `apps/production/`:

- `apps/production/myapp-values.yaml` — a HelmRelease with the same
  name and namespace, patch-style:
  ```yaml
  apiVersion: helm.toolkit.fluxcd.io/v2
  kind: HelmRelease
  metadata:
    name: myapp
    namespace: myapp
  spec:
    values:
      env:
        MYAPP_URL: https://myapp.passer.lan
        MYAPP_LOG_LEVEL: INFO
  ```
- `apps/production/myapp-httproute.yaml` (rare — only if the base
  HTTPRoute needs to change for production, e.g. adding a second
  hostname).

## 4. Register in the production overlay

Edit `apps/production/kustomization.yaml`:

```yaml
resources:
  - ...
  - ../base/myapp
patches:
  - path: myapp-values.yaml
    target: { kind: HelmRelease, name: myapp }
  # only if you have a base httproute override:
  # - path: myapp-httproute.yaml
  #   target: { kind: HTTPRoute, name: myapp }
```

## 5. Validate locally

```bash
kubectl kustomize --load-restrictor=LoadRestrictionsNone apps/production >/dev/null \
  && echo OK-production
```

If this errors, fix the manifests before pushing — Flux will refuse
to apply anything if the kustomize build fails.

## 6. Commit and push

```bash
git add apps/base/myapp apps/production/kustomization.yaml apps/production/myapp-values.yaml
git status                                    # confirm no plaintext secret slipped in
grep -L 'ENC\[' apps/base/myapp/*.secret.yaml # should print nothing
git commit -m "Add myapp"
git push
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization apps -n flux-system
```

## 7. Verify

```bash
kubectl -n myapp get pods -w
kubectl -n myapp get httproute myapp -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].message}{"\n"}'
curl -skI https://myapp.passer.lan/ --max-time 5
```

## 8. Optionally wire SSO

If the app speaks OIDC (Nextcloud, Immich, Paperless, Findash …), add
a provider + application block to
`apps/base/authentik/authentik-blueprints.secret.yaml` (SOPS-encrypted)
and a matching `myapp-oidc` Secret in `apps/base/myapp/`. Full
pattern: `docs/AUTHENTIK-SSO.md`.

## 9. Optionally add to Velero

If the app has state worth backing up, extend the schedule in
`infrastructure/velero-schedules/` to include the namespace. See
`docs/velero-backups.md` for the schedule format.

## 10. Optionally list it on the landing page

Edit `apps/base/passer-home/index.html` and add a line in the
**Services** list. The ConfigMap for the landing page is regenerated
on every reconcile, so the change goes live automatically.
