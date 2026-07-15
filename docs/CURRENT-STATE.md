# Current State

Date: 2026-06-29

## Healthy

- Control plane `192.168.178.200` is reachable.
- Workers `192.168.178.201`, `192.168.178.202`, and `192.168.178.203` are healthy.
- `infra-configs` is `Ready`.
- `authentik` is installed and healthy.
- `immich` is installed and healthy.
- Gateway API routes for the main apps are accepted by Envoy.

## Known Issues

- `apps` is blocked because `nextcloud` is stuck in a failed upgrade cycle.
- Local resolver lookups from this environment return `NXDOMAIN` for `*.passer.lan`.
- Querying CoreDNS directly at `192.168.178.241` returns the expected records.
- The cluster-side route for `immich.passer.lan` is healthy; the DNS path on the client side is the problem.

## Useful Checks

```bash
flux get kustomizations -A
kubectl -n nextcloud get helmrelease nextcloud
kubectl -n nextcloud describe pod nextcloud-6fbd87c88b-g4mqf
nslookup immich.passer.lan 192.168.178.241
```
