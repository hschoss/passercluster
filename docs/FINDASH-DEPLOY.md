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

## Zugriff vom Laptop über Headscale (aquila)

Findash ist bewusst nicht via Envoy/`passer.lan` ins LAN exposed
sondern über das Headscale-Tailnet auf aquila, als
`findash.tail.schloschi.com`. Keine public DNS, keine Portfreigabe am
Heim-Router. Zugang hat jedes Device, das im Tailnet des Users
`hannes` eingeloggt ist (Laptop, iPhone, VPS-Node).

### Einmalige Bootstrap-Schritte

1. **Pre-Auth-Key am Headscale generieren** (auf aquila):
   ```bash
   ssh aquila
   docker exec headscale headscale preauthkeys create \
     --user hannes --reusable --expiration 24h
   ```
   Rückgabe-Hex-String merken.

2. **Secret im Cluster anlegen** (nicht in Git, Pre-Auth-Key =
   Credential; einmal verbraucht wird er durch das Pod-State-PVC
   überflüssig):
   ```bash
   kubectl -n finance create secret generic headscale-authkey \
     --from-literal=TS_AUTHKEY='<der-key>'
   ```

3. **Flux reconcile** stößt Deployment + PVC an:
   ```bash
   flux reconcile kustomization apps -n flux-system
   # oder per kubectl annotate
   ```

4. **Headscale-Side Node registriert sich**: in ca. 30 s meldet sich
   der neue Node `findash` im Headscale an:
   ```bash
   ssh aquila "docker exec headscale headscale nodes list"
   ```
   Sollte als zusätzliche Zeile `findash` (User `hannes`,
   100.64.0.x) erscheinen.

5. **MagicDNS prüfen** — vom Laptop:
   ```bash
   dig +short findash.tail.schloschi.com
   # ergibt die 100.64.0.x
   ```

### Zugriff

Mit aktivem Tailscale-Client:
```
https://findash.tail.schloschi.com
```
TLS-Zertifikat wird vom Tailnet (ACME via tailscale cert) ausgegeben
und ist in Tailscale-Clients automatisch vertrauenswürdig. Erster
Request kann 1-2 s dauern (Cert-Ausstellung).

Solange der Findash-Service noch den Placeholder serviert, antwortet
die Tailnet-URL mit dem Placeholder. Nach dem oben beschriebenen Flip
zeigt sie das echte Dashboard.

### Rollback / Entfernen

```bash
# aus dem Cluster
kubectl -n finance delete deployment findash-tailnet
kubectl -n finance delete pvc findash-tailnet-state
kubectl -n finance delete secret headscale-authkey

# aus Headscale den Node entsorgen
ssh aquila "docker exec headscale headscale nodes delete -i <node-id>"
```

### Falls jemals doch public (ohne Tailscale-Client erreichbar)

Caddy auf aquila kriegt einen zusätzlichen Block, der an die
Tailnet-IP des Clusters-Nodes proxied. Siehe
`REQUIREMENTS §6` und einen separaten Follow-up Commit — bisher
nicht konfiguriert und nicht empfohlen für Findash.

## Source database

The upstream price database (`SOURCE_DATABASE_URL` in `.env.example`)
is intentionally left empty in `findash-config`. `findash sync` refuses
to run without it. As soon as that DB is reachable from the cluster,
either add the value to `findash-config` (if it is not sensitive) or
promote it into `findash-db.secret.yaml` as an extra key and reference
it via `envFrom`.
