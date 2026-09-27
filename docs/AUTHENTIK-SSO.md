# Authentik SSO – application wiring

Authentik is reachable at both:

- `https://auth.passer.lan`
- `https://authentik.passer.lan`

They resolve to the same Envoy Gateway (`192.168.178.240`) and hit the same
`authentik-server` service. Use whichever you prefer; the redirect URIs used
by the OIDC clients below all point at `auth.passer.lan`.

## What GitOps ships

`apps/base/authentik/authentik-blueprints.secret.yaml` is a SOPS-encrypted
Authentik blueprint. On every Authentik startup it re-creates:

| App        | Client ID   | Application slug | Redirect URI                                                                 |
|------------|-------------|------------------|------------------------------------------------------------------------------|
| Nextcloud  | `nextcloud` | `nextcloud`      | `https://nextcloud.passer.lan/apps/user_oidc/code`                            |
| Immich     | `immich`    | `immich`         | `https://immich.passer.lan/auth/login` + `.../user-settings` + `app.immich:///oauth-callback` |
| Paperless  | `paperless` | `paperless`      | `https://paperless.passer.lan/accounts/oidc/authentik/login/callback/`        |
| Jellyfin   | `jellyfin`  | `jellyfin`       | `https://jellyfin.passer.lan/sso/OID/redirect/authentik` + `/sso/OID/r/authentik` |

Vaultwarden is **not** in the blueprint – see the caveats below.

Client secrets are pinned in the blueprint (SOPS-encrypted) and matched by
per-app secrets in each app's namespace so the app can consume them:

- `nextcloud/nextcloud-oidc`
- `immich/immich-oidc`
- `paperless-ngx/paperless-oidc`

Read the raw values with:

```bash
kubectl -n <ns> get secret <name>-oidc -o jsonpath='{.data.OIDC_CLIENT_SECRET}' | base64 -d
```

## Per-app status

### Paperless-ngx – fully declarative

`apps/base/paperless-ngx/release.yaml` sets `PAPERLESS_APPS` and injects
`PAPERLESS_SOCIALACCOUNT_PROVIDERS` (JSON blob with the OIDC config) from
`paperless-oidc`. After the HelmRelease reconciles, `paperless.passer.lan`
should show a "Sign in with Authentik" button next to the normal login.

`PAPERLESS_SOCIAL_AUTO_SIGNUP=true` means Authentik users that don't exist in
Paperless yet get auto-created on first login. Local login (the
`PAPERLESS_ADMIN_USER` account) still works as a fallback.

### Nextcloud – bootstrap Job wires it up

The chart itself doesn't know about OIDC, so `nextcloud-oidc-bootstrap.job.yaml`
runs after each reconcile:

1. Waits for the `nextcloud` deployment to be ready.
2. Installs the `user_oidc` app if missing.
3. Runs `occ user_oidc:provider Authentik --clientid=… --clientsecret=… --discoveryuri=…`.

The Job is idempotent – it re-applies the same settings safely. Local login
via `NEXTCLOUD_ADMIN_USER` still works.

If the Job fails (e.g. Nextcloud not up yet, or user_oidc needs a manual
`app:install`), inspect it:

```bash
kubectl -n nextcloud logs job/nextcloud-oidc-bootstrap
kubectl -n nextcloud delete job nextcloud-oidc-bootstrap   # let Flux re-create it
```

### Immich – finish in the admin UI

Immich configures OAuth via System Settings, and using
`IMMICH_CONFIG_FILE` would reset every other admin setting to defaults.
So this repo pre-creates the client in Authentik and stores the credentials
in `immich/immich-oidc`, but the last mile is a UI paste:

1. Log in to `https://immich.passer.lan` as admin.
2. Go to **Administration → Settings → Authentication → OAuth**.
3. Paste:
   - **Issuer URL**: `https://auth.passer.lan/application/o/immich/`
   - **Client ID**: `immich`
   - **Client Secret**: `kubectl -n immich get secret immich-oidc -o jsonpath='{.data.OIDC_CLIENT_SECRET}' | base64 -d`
   - **Scope**: `openid email profile`
   - **Button Text**: `Login with Authentik`
   - Enable **Auto-register**.

### Jellyfin – needs a plugin

Jellyfin doesn't ship OIDC. The community plugin is
[`jellyfin-plugin-sso`](https://github.com/9p4/jellyfin-plugin-sso). To wire
it up:

1. In Jellyfin UI → **Dashboard → Plugins → Repositories**, add
   `https://raw.githubusercontent.com/9p4/jellyfin-plugin-sso/manifest-release/manifest.json`.
2. Install **SSO-Auth** from the plugin catalog, restart Jellyfin.
3. **Dashboard → SSO** → add provider `authentik`:
   - OID Endpoint: `https://auth.passer.lan/application/o/jellyfin/`
   - OID Client ID: `jellyfin`
   - OID Secret: `kubectl -n authentik get secret authentik-blueprints …` (or copy from the blueprint)
   - Enable Authorization by Plugin, add default role `Users`.

The Authentik-side OIDC provider is already there – no UI clicks needed on
the Authentik dashboard.

### Vaultwarden – no OIDC in this repo

Upstream Vaultwarden does **not** implement OIDC / SAML / any SSO – SSO in
Bitwarden is an Enterprise-only feature. Options if you want SSO here:

- Run the community fork `timshel/vaultwarden` which adds SSO.
- Put Authentik in front via a Proxy Provider + Envoy `SecurityPolicy` /
  ExtAuth. **Warning:** this breaks every Vaultwarden client (browser
  extension, desktop, mobile) because none of them can walk an OIDC flow.
  Only the web UI at `vaultwarden.passer.lan` would be protected.

Given how mobile-heavy Vaultwarden usage is, this repo keeps its native
login as-is. Access is protected by the local admin password + registration
lockout; document that decision if it changes.

## Regenerating a client secret

Client secrets live inside the blueprint. To rotate:

```bash
sops apps/base/authentik/authentik-blueprints.secret.yaml
# edit the client_secret for the app in question
sops apps/base/<app>/<app>-oidc.secret.yaml
# match the new value
git commit && git push
```

Flux reconciles the blueprint on the next Authentik pod restart (or
`flux reconcile helmrelease -n authentik authentik`), then the app secret,
then the app picks up the change.
