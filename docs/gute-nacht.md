# Gute Nacht Hand-off

This note captures the important current state of the Flux/GitHub Actions E2E path so the next session can continue without re-discovering the repo layout.

## What This Covers

- the intended E2E reconciliation graph
- the current GitHub Actions workflow shape
- the expected Flux Kustomizations and HelmReleases
- the app and gateway checks used by CI
- the most common failure modes and diagnostics
- the local commands that are worth running first

## Current E2E Path

The E2E workflow in `.github/workflows/e2e.yaml` currently does the following:

1. checks out the repository
2. prints the current commit and git status
3. installs Flux into a kind cluster
4. seeds `passer-lan-tls` into `envoy-gateway-system`
5. creates the Flux source and root Kustomization for `./clusters/e2e`
6. waits for the root `flux-system` Kustomization
7. waits for the expected child Kustomizations
8. waits for all HelmReleases that actually exist in the cluster
9. verifies gateway routing with `podinfo-e2e.passer.lan`
10. prints debug information on failure

## Expected Reconciliation Graph

The currently expected graph is:

```text
flux-system
→ infra-controllers
→ infra-configs
→ apps
→ HelmReleases
→ gateway / HTTPRoute / podinfo readiness
```

Do not assume optional resources are present. Only wait for what the E2E overlay actually creates.

## Important Names and Paths

### Flux overlays

- `clusters/e2e/kustomization.yaml`
- `clusters/production/infrastructure.yaml`
- `clusters/production/apps.yaml`
- `clusters/staging/infrastructure.yaml`
- `clusters/staging/apps.yaml`

### E2E app

- namespace: `podinfo`
- HelmRelease: `podinfo/podinfo`
- host: `podinfo-e2e.passer.lan`
- gateway namespace: `envoy-gateway-system`

### Expected child Kustomizations in E2E

- `infra-controllers`
- `infra-configs`
- `apps`

### Expected HelmReleases in E2E

- `cert-manager/cert-manager`
- `envoy-gateway-system/envoy-gateway`
- `podinfo/podinfo`

Namespace and name may be equal. That is valid and must not be rejected.

## Workflow Details That Matter

### Do this early

The workflow should always print:

```bash
git rev-parse HEAD
git status --short
```

That makes it obvious which commit the CI runner is executing.

### Do not parse tables

Do not build logic from human-readable output like `kubectl get ...` tables.

Use structured extraction instead:

- `jsonpath` for Kustomizations
- `jsonpath` namespace/name pairs for HelmReleases

### HelmRelease wait rule

The important validation rule is:

- reject malformed entries
- allow `namespace == name`

Valid examples:

- `cert-manager|cert-manager`
- `podinfo|podinfo`

Invalid examples:

- missing delimiter
- empty namespace
- empty name
- too many delimiters

### Gateway routing check

The gateway smoke test should use a deterministic Envoy service selection.

Useful selector:

```text
gateway.envoyproxy.io/owning-gateway-name=envoy
```

If the workflow needs a service list, print the services first and then pick the first matching service deterministically.

## Common Failure Modes

### Missing Flux Kustomization

Symptom:

- `kubectl wait` says the resource is not found
- the workflow stalls while waiting for `infra-controllers`, `infra-configs`, or `apps`

Check:

```bash
kubectl -n flux-system get kustomizations -o wide
kubectl -n flux-system describe kustomization flux-system
```

### Malformed HelmRelease wait

Symptom:

- a log line like `Waiting for HelmRelease: cert-manager cert-manager/`
- `kubectl wait` complains about invalid resource/name syntax

Fix:

- use `namespace/name`
- pass the namespace with `-n "$namespace"`
- use `helmrelease.helm.toolkit.fluxcd.io/${name}` as the wait target

### HelmRelease stuck installing

Symptom:

- HelmRelease stays `Unknown` or `InProgress`
- the workflow times out after a long wait

Check:

```bash
kubectl -n <namespace> describe helmrelease <name>
kubectl -n <namespace> get events --sort-by=.lastTimestamp | tail -n 50
kubectl -n flux-system logs deploy/helm-controller --tail=150
```

### Invalid E2E overlay

Symptom:

- `kubectl kustomize clusters/e2e` fails
- the overlay references a missing file such as `artifacts.yaml`

Check the exact files under `clusters/e2e/` before adding them to `kustomization.yaml`.

### Gateway or HTTPRoute not ready

Symptom:

- podinfo is deployed but the curl check fails
- the Envoy service cannot be found or the route is not attached

Check:

```bash
kubectl get gateways.gateway.networking.k8s.io -A -o wide
kubectl get httproutes.gateway.networking.k8s.io -A -o wide
kubectl -n envoy-gateway-system get svc -o wide
```

### Missing TLS secret

Symptom:

- gateway or route reconciliation fails because `passer-lan-tls` is not present

Check:

```bash
kubectl get secret passer-lan-tls -A
```

The workflow seeds the secret in `envoy-gateway-system` before Flux reconciliation starts.

## Useful Local Commands

```bash
git diff --check
./scripts/validate.sh
kubectl kustomize clusters/e2e
kubectl kustomize apps/e2e
flux get kustomizations -A
flux get helmreleases -A
```

If you have a kind cluster available, try the E2E path locally with the same Flux install and reconciliation order that CI uses.

## Debug Bundle

If CI fails, gather:

```bash
kubectl get ns
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp | tail -n 200
kubectl -n flux-system get gitrepositories,kustomizations,helmreleases -o wide
kubectl -n flux-system describe kustomizations
kubectl get helmreleases.helm.toolkit.fluxcd.io -A -o wide
kubectl get gateways.gateway.networking.k8s.io -A -o wide
kubectl get httproutes.gateway.networking.k8s.io -A -o wide
kubectl -n flux-system logs deploy/source-controller --tail=150
kubectl -n flux-system logs deploy/kustomize-controller --tail=150
kubectl -n flux-system logs deploy/helm-controller --tail=150
```

Use `|| true` around optional commands if you are collecting these inside a failure hook.

## Notes For The Next Session

- The E2E overlay is intentionally lightweight and should not be expanded into the full staging tree.
- Keep the workflow deterministic.
- Keep the HelmRelease and Kustomization waits structured, not table-parsed.
- The backup documentation now lives in `docs/VELERO-SETUP.md`.
