# Findash deployment

`finance.passer.lan` currently serves an nginx placeholder from
`apps/base/finance/`. Everything else needed to run the real Dash app
(namespace, Postgres via CNPG, DB secret, migration Job, Service,
HTTPRoute) is already in `apps/base/finance/findash.yaml` and
`findash-db.secret.yaml`, they are just not yet listed in the local
`kustomization.yaml`.

## What is still missing

An OCI image. The Dockerfile at
`~/gh/longterm-stock-dashboard-py/docker/Dockerfile` is ready — it just
needs to be built and pushed to a registry the cluster can pull from.

## Building and pushing the image

```bash
cd ~/gh/longterm-stock-dashboard-py

# Log in once — a Personal Access Token with write:packages is enough.
echo $CR_PAT | docker login ghcr.io -u hschoss --password-stdin

TAG=$(git rev-parse --short HEAD)
docker build -f docker/Dockerfile -t ghcr.io/hschoss/findash:$TAG -t ghcr.io/hschoss/findash:latest .
docker push ghcr.io/hschoss/findash:$TAG
docker push ghcr.io/hschoss/findash:latest
```

Make the package public in the GitHub Packages UI (or keep it private and
add an imagePullSecret to the `finance` namespace).

## Flipping the finance namespace over

1. Edit `apps/base/finance/kustomization.yaml`:
   - Remove `placeholder-deployment.yaml` from `resources`
   - Uncomment `findash.yaml` and `findash-db.secret.yaml`
   - Remove the two `configMapGenerator` entries (nginx-conf and www) —
     the placeholder ConfigMaps are no longer referenced.
2. Edit `apps/base/finance/httproute.yaml`, change the backendRef to:
   ```yaml
   - name: findash
     port: 5000
   ```
3. Edit `apps/base/finance/findash.yaml`: pin the container image to the
   tag you pushed (both in the Deployment and in the migration Job).

Commit, push. Flux applies. The Job runs `alembic upgrade head` and
`findash seed-demo`; the Deployment comes up and starts answering on
`finance.passer.lan`.

To roll back to the placeholder, revert the above three edits.

## Source database

The upstream price database (`SOURCE_DATABASE_URL` in `.env.example`)
is intentionally left empty in `findash-config`. `findash sync` refuses
to run without it. As soon as that DB is reachable from the cluster,
either add the value to `findash-config` (if it is not sensitive) or
promote it into `findash-db.secret.yaml` as an extra key and reference
it via `envFrom`.
