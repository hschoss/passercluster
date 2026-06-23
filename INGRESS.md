# Passer LAN Routing

Private services are exposed as `service.passer.lan` names.

Current model:

- Pi-hole on `passer` handles LAN DNS.
- Envoy Gateway in Kubernetes is the reverse proxy.
- Services are published with Gateway API `HTTPRoute` resources.
- ExternalDNS and CoreDNS keep the cluster records in sync.

Example names:

- `api.passer.lan` -> service A
- `app.passer.lan` -> service B
- `grafana.passer.lan` -> monitoring service

Flow:

```text
LAN client
  -> Pi-hole DNS
  -> Envoy Gateway / Kubernetes
  -> application service
```

Implementation notes:

- Use `HTTPRoute` for service exposure.
- Keep the wildcard gateway hostname at `*.passer.lan`.
- Keep app URL settings aligned with the public hostname.
- Use Pi-hole local records or forwarding rules only for DNS, not ingress.
