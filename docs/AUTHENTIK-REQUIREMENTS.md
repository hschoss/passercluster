# Authentik Requirements Review

This document captures the design checks for the Authentik rollout and
separates the browser-gate model from full application SSO.

## Verified Points

- Forward auth uses the reverse proxy and an outpost to check auth state.
- Proxy providers are the right fit for apps that do not support OIDC or SAML.
- Single-hostname forward auth is the right model for one app per subdomain.
- Domain-level forward auth exists, but it weakens per-app policy boundaries.
- authentik supports OIDC, so native app SSO can be added later where useful.
- Docker Compose is acceptable for small production or homelab installs.

## Corrections

- Use `http://<server>:9000` only for the first bootstrap, not for daily access.
- Do not mount host timezone files into authentik containers.
- Keep PostgreSQL passwords below the documented limit.

## Recommendation

Use one Application and one Proxy Provider per protected hostname, then add
OIDC only for apps that benefit from it.
