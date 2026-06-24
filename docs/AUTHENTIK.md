# Authentik

## Purpose

Authentik is the primary browser login gateway for the homelab.
It will eventually sit in front of the hosted services through forward auth and, where supported, native OIDC or LDAP.

## First bootstrap

Authentik's documented first setup is done on port `9000`.
In this cluster the easiest way to reach that endpoint is port-forwarding the service:

```bash
kubectl -n authentik port-forward svc/authentik-server 9000:80
```

Then open:

```text
http://127.0.0.1:9000
```

## Daily access

After bootstrap, the normal URL is:

```text
https://auth.passer.lan
```

## What this repo installs

- Authentik Helm chart from `charts.goauthentik.io`
- A dedicated `authentik` namespace
- A dedicated CloudNativePG database cluster
- SOPS-encrypted secrets for the Authentik secret key and database credentials
- A Gateway API route on `auth.passer.lan`

## Next step

After the initial admin account is created, add proxy providers and applications for the services you want protected.
That is the step that turns Authentik from a standalone login portal into the primary gate for the rest of the stack.
