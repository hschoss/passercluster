# Plan

Authentik is installed. The remaining work is to turn it into the cluster-wide
login gate and register each exposed app in a maintainable way.

## Next Steps

1. Keep `authentik` on `auth.passer.lan` as the human login entry point.
2. Create one proxy application/provider pair for each exposed app:
   - `podinfo.passer.lan`
   - `nextcloud.passer.lan`
   - `jellyfin.passer.lan`
   - `vaultwarden.passer.lan`
   - `immich.passer.lan`
   - `paperless.passer.lan`
3. Exclude Authentik itself from protection so the portal remains reachable.
4. Attach the embedded outpost to the proxy providers.
5. Add one Envoy Gateway `SecurityPolicy` per app `HTTPRoute`.
6. Keep the public hostnames unchanged and protect them at the edge.
7. Make the Authentik app tiles launch the same hostnames the gateway protects.
8. Validate the manifests before reconciling Flux.
9. Test the end-to-end browser flow after the policies are in place.

## Current References

- `apps/base/authentik/`
- `apps/production/authentik-values.yaml`
- `docs/AUTHENTIK.md`
