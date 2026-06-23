# Operations Guide

This repository is managed through Flux. The practical rule is simple: edit Git, then reconcile the affected Flux layer, then verify the live objects.

## Reconcile Order

Reconcile in this order when making infrastructure or app changes:

1. `infra-controllers`
2. `infra-configs`
3. `infra-velero`
4. `infra-velero-schedules`
5. `apps`

Example commands:

```bash
flux get kustomizations -A
flux reconcile kustomization infra-controllers -n flux-system
flux reconcile kustomization infra-configs -n flux-system
flux reconcile kustomization infra-velero -n flux-system
flux reconcile kustomization apps -n flux-system
```

## What To Verify

After a reconcile, confirm the following:

```bash
kubectl get gateway -A
kubectl get httproute -A
kubectl get certificate -A
kubectl get svc -A | grep LoadBalancer
kubectl get pods -A
```

Expected signals for a healthy cluster:

- Flux kustomizations report `Ready`
- the Envoy Gateway has the expected LoadBalancer IP
- HTTPRoutes are attached to the gateway
- the wildcard certificate secret exists for `passer.lan`
- application namespaces have running pods

## Network Model

The public path through the LAN is:

`LAN client -> Pi-hole -> CoreDNS -> Envoy Gateway -> application service`

Current fixed IPs:

- Envoy Gateway: `192.168.178.240`
- CoreDNS: `192.168.178.241`

The canonical service domain is `passer.lan`.

## DNS And TLS

- `ExternalDNS` watches `gateway-httproute` sources and writes `passer.lan` records into CoreDNS.
- `cert-manager` issues the internal wildcard certificate used by Envoy.
- Browsers that do not trust the internal CA will show the normal self-signed warning until the CA is installed on the client.

## Storage Model

Longhorn handles persistent storage for the stateful workloads. Use the dedicated storage documentation before changing disks, node labels, or recurring job definitions:

- [Longhorn notes](../infrastructure/longhorn-README.md)
- `scripts/longhorn-validate-disks.sh`
- `scripts/longhorn-health-check.sh`

## Talos Checks

If a node or control plane issue is suspected, use Talos rather than SSH:

```bash
cd ~/gh/passercluster/talos
talosctl health --nodes 192.168.178.200 --endpoints 192.168.178.200 --talosconfig ./talosconfig
talosctl dashboard --nodes 192.168.178.200 --endpoints 192.168.178.200 --talosconfig ./talosconfig
```

## Before Pushing

1. Run `git status` and confirm that only intended files are staged.
2. Keep secrets, recovery dumps, and local config snapshots out of the commit.
3. Prefer small commits that map to one change in the GitOps tree.
4. If you changed hostnames, update the app URL values and HTTPRoutes together.
