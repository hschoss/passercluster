# Homelab DNS and TLS Setup

This cluster uses `.homelab` names for private services only. FritzBox remains the primary DNS resolver for clients, and only the `.homelab` zone is conditionally forwarded to the in-cluster CoreDNS LoadBalancer.

## DNS Flow

- Primary client DNS: FritzBox.
- Conditional forwarding zone: `homelab`.
- Conditional forwarding target: `192.168.178.240`, the `homelab-coredns` LoadBalancer from `infrastructure/controllers/coredns.yaml`.
- Dynamic records: ExternalDNS watches Gateway API `HTTPRoute` objects and writes `.homelab` records to the CoreDNS etcd backend.
- Failure behavior: if the cluster or CoreDNS is unavailable, `.homelab` lookups fail, but normal internet DNS continues through FritzBox.

## FritzBox Conditional Forwarding

1. Open the FritzBox web UI.
2. Go to `Home Network` -> `Network` -> `Network Settings`.
3. Find the DNS or local DNS server settings for conditional forwarding.
4. Add a conditional forwarding entry:
   - Domain: `homelab`
   - DNS server: `192.168.178.240`
5. Save the configuration.
6. From a client on the LAN or VPN, test a service name:

```bash
nslookup nextcloud.homelab
nslookup immich.homelab
```

## TLS Trust

cert-manager creates an internal CA with `selfsigned-bootstrap`, then uses `selfsigned-issuer` for `.homelab` certificates. The Envoy Gateway HTTPS listener uses the `wildcard-homelab-tls` certificate.

To install the homelab CA on a client:

```bash
kubectl get secret -n cert-manager homelab-root-ca -o jsonpath='{.data.tls\.crt}' | base64 -d > homelab-root-ca.crt
```

Install `homelab-root-ca.crt` into the operating system or browser trust store. Without this step, browsers will show a certificate warning, which is expected for a private CA.

## VPN Access

VPN clients should use FritzBox as their DNS server so the same conditional forwarding rule applies remotely. After connecting to the VPN, verify:

```bash
nslookup vaultwarden.homelab
curl -I https://vaultwarden.homelab
```

If VPN clients use a different DNS server, add a VPN DNS rule that forwards `homelab` to FritzBox or directly to `192.168.178.240`.

## Service URLs

- Nextcloud: `https://nextcloud.homelab`
- Immich: `https://immich.homelab`
- Jellyfin: `https://jellyfin.homelab`
- Vaultwarden: `https://vaultwarden.homelab`
- Podinfo: `https://podinfo.homelab`
- Longhorn: `https://longhorn.homelab`

Staging services keep separate names where staging overlays exist:

- Nextcloud staging: `https://nextcloud-staging.homelab`
- Jellyfin staging: `https://jellyfin-staging.homelab`
- Vaultwarden staging: `https://vaultwarden-staging.homelab`
- Podinfo staging: `https://podinfo-staging.homelab`

## Operations

Useful checks after Flux reconciles:

```bash
kubectl get helmrelease -A
kubectl get svc -n homelab-dns homelab-coredns
kubectl get pods -n external-dns
kubectl get clusterissuer
kubectl get certificate -A
kubectl get httproute -A
```

The CoreDNS LoadBalancer IP must stay outside the FritzBox DHCP pool. The current MetalLB pool is `192.168.178.240-192.168.178.250`, and CoreDNS reserves `192.168.178.240`.
