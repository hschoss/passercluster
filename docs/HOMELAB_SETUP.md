# Passer LAN DNS and TLS Setup

This cluster uses `passer.lan` for private service names. Pi-hole on `passer` is the LAN DNS entrypoint, and Envoy Gateway in Kubernetes is the actual reverse proxy for HTTP and HTTPS traffic.

## DNS Flow

- Clients query Pi-hole on `passer`.
- Pi-hole resolves or forwards `passer.lan` names to the cluster DNS path.
- Envoy Gateway listens on `192.168.178.240`.
- CoreDNS listens on `192.168.178.241` and serves cluster-local DNS records published by ExternalDNS.
- ExternalDNS watches Gateway API `HTTPRoute` objects and writes `passer.lan` records into the CoreDNS etcd backend.

## Pi-hole Rules

1. Open the Pi-hole admin UI.
2. Add the `passer.lan` records or forwarding rule you need.
3. Keep the gateway address pointed at `192.168.178.240`.
4. Keep cluster-local DNS pointing at `192.168.178.241` if you want dynamic records from ExternalDNS.
5. Test resolution from a LAN client:

```bash
nslookup nextcloud.passer.lan
nslookup immich.passer.lan
```

## TLS Trust

cert-manager creates an internal CA with `selfsigned-bootstrap`, then uses `selfsigned-issuer` for `passer.lan` certificates. The Envoy Gateway HTTPS listener uses the wildcard certificate for `passer.lan`.

To install the internal CA on a client:

```bash
kubectl get secret -n cert-manager homelab-root-ca -o jsonpath='{.data.tls\.crt}' | base64 -d > homelab-root-ca.crt
```

Install `homelab-root-ca.crt` into the operating system or browser trust store if you want browsers to trust the private certificates.

## Service URLs

- Nextcloud: `https://nextcloud.passer.lan`
- Immich: `https://immich.passer.lan`
- Jellyfin: `https://jellyfin.passer.lan`
- Vaultwarden: `https://vaultwarden.passer.lan`
- Podinfo: `https://podinfo.passer.lan`
- Longhorn: `https://longhorn.passer.lan`

Staging services keep separate names where staging overlays exist:

- Nextcloud staging: `https://nextcloud-staging.passer.lan`
- Jellyfin staging: `https://jellyfin-staging.passer.lan`
- Vaultwarden staging: `https://vaultwarden-staging.passer.lan`
- Podinfo staging: `https://podinfo-staging.passer.lan`

## Operations

```bash
kubectl get helmrelease -A
kubectl get svc -n homelab-dns homelab-coredns
kubectl get pods -n external-dns
kubectl get clusterissuer
kubectl get certificate -A
kubectl get httproute -A
```

The CoreDNS LoadBalancer IP must stay outside the DHCP pool. The current MetalLB pool is `192.168.178.240-192.168.178.250`, Envoy uses `192.168.178.240`, and CoreDNS reserves `192.168.178.241`.

## Adding A Domain

1. Add or update the service's `HTTPRoute` hostname in the repo.
2. Update any app-level URL setting such as `PAPERLESS_URL` or the Nextcloud host config.
3. Make sure the hostname ends in `passer.lan`.
4. Reconcile Flux.
5. Verify the new name resolves through Pi-hole and returns the app.

## Deleting A Domain

1. Remove the hostname from the service's `HTTPRoute`.
2. Remove any app-level URL or trusted-domain setting for that name.
3. Remove any matching Pi-hole local DNS record if one exists.
4. Reconcile Flux.
5. Confirm the old name no longer resolves.
