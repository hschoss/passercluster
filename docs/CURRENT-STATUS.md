# Authentik Status

Date: 2026-06-29

## What Is Done

- Authentik is installed in its own namespace.
- The Authentik HelmRelease is healthy.
- PostgreSQL for Authentik is provisioned in-cluster.
- The public Authentik hostname is `https://auth.passer.lan`.
- The first-bootstrap helper is available at `scripts/authentik-bootstrap.sh`.

## What Is Still Missing

- Proxy application/provider pairs have not been created for the protected apps.
- The embedded outpost is not yet wired into per-app access policy.
- Envoy Gateway `SecurityPolicy` objects are not yet enforcing Authentik at the edge.
- The apps still behave as independent public services.

## Next Step

The next implementation step is to create one proxy provider per exposed app,
attach the outpost, and then add the gateway policy layer so browser traffic
must pass through Authentik first.
