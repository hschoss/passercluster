# E2E Flux Fix Notes

## Summary

- Added a dedicated CI-only Flux overlay at `clusters/e2e/`.
- Added a dedicated CI-only app overlay at `apps/e2e/`.
- Updated the GitHub Actions workflow to bootstrap Flux against the lighter e2e overlay instead of the full staging stack.
- Updated the gateway smoke test to use `podinfo-e2e.passer.lan`.
- Seeded a temporary `passer-lan-tls` Secret in the Kind-based E2E cluster before waiting on `apps`.

## Why

The staging overlay includes heavier workloads that make the Kind-based CI
environment slower and less deterministic.

The e2e overlay keeps the smoke test focused on one fast, routable app.

## Still To Verify

- The workflow seeds `passer-lan-tls` in `envoy-gateway-system` before bootstrapping Flux, then waits for `flux-system` and the expected child Kustomizations `infra-controllers`, `infra-configs`, and `apps` to become `Ready` before verifying `podinfo` separately.
- The e2e overlay now has a real `clusters/e2e/kustomization.yaml` entrypoint so Flux can render the CI resources deterministically.
- The E2E run needs a temporary TLS secret in `envoy-gateway-system` so Envoy Gateway can serve HTTPS in Kind.
- The CI-only `apps` Kustomization intentionally does not wait on workload health; the HelmRelease check covers that explicitly.
- The `podinfo-e2e.passer.lan` route should be attached before the curl check runs.
