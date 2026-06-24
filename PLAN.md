# Plan

1. Read the Authentik requirements and the repo layout so I can match the existing GitOps pattern.
2. Inspect the live cluster to confirm the current namespaces, ingress path, storage classes, and whether Authentik already exists.
3. Review the official Authentik Kubernetes documentation and chart metadata to confirm the supported install flow, bootstrap behavior, and current chart version.
4. Add an Authentik app base to the repo with a HelmRepository, HelmRelease, encrypted credentials, and a dedicated PostgreSQL cluster.
5. Patch the production overlay to enable the Authentik route on `auth.passer.lan`.
6. Update the service map so the new login endpoint is documented.
7. Validate the rendered manifests and then reconcile Flux so the cluster picks up the change.
