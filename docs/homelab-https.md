# Homelab HTTPS

This repository uses HTTPS for internal `passer.lan` services, but it does not
depend on a public CA or cert-manager for the `passer.lan` certificate.

## Scope

- Domain base: `passer.lan`
- Covered names:
  - `passer.lan`
  - `*.passer.lan`
- Intended use:
  - LAN-only access
  - VPN access
  - no public exposure

Browsers will warn that the certificate is self-signed. That is expected.
The goal here is encrypted transport, not browser-trusted public PKI.

## Certificate generation

Generate the certificate and private key locally:

```bash
./scripts/generate-passer-lan-cert.sh
```

This writes:

- `secrets/passer-lan.crt`
- `secrets/passer-lan.key`

The key file is private. It is ignored by Git and must not be committed.

## Secret rollout

Push the certificate into every namespace that exposes a `passer.lan` service
or route:

```bash
./scripts/apply-passer-lan-tls-secret.sh
```

The script creates or updates a `kubernetes.io/tls` Secret named
`passer-lan-tls` in:

- application namespaces discovered from the repo
- `envoy-gateway-system`

It uses:

```bash
kubectl create secret tls ... --dry-run=client -o yaml | kubectl apply -f -
```

## Gateway wiring

The Envoy Gateway HTTPS listener terminates TLS with `passer-lan-tls`.
The listener is not locked to only `*.passer.lan`, so the same certificate can
cover the apex domain and wildcard subdomains.

Current HTTP routes still publish the service hostnames, for example:

- `immich.passer.lan`
- `nextcloud.passer.lan`
- `jellyfin.passer.lan`
- `vaultwarden.passer.lan`
- `paperless.passer.lan`
- `podinfo.passer.lan`
- `longhorn.passer.lan`
- `auth.passer.lan`

## Verification

```bash
kubectl get ingress -A
kubectl get httproute -A
kubectl get secret passer-lan-tls -A
curl -k https://passer.lan
curl -k https://immich.passer.lan
openssl s_client -connect passer.lan:443 -servername passer.lan
```

If you add a new `Ingress` or `HTTPRoute`, re-run the secret rollout script so
the namespace gets the TLS secret before the controller reconciles the route.

## Security notes

- `passer-lan.key` must stay out of Git.
- `secrets/` is ignored so local certificate material stays local.
- Self-signed HTTPS encrypts traffic, but without client trust it does not
  provide public-style browser identity verification.
- This setup is only for internal LAN/VPN use.
