# Passercluster Operator Runbook

## Scope

This is the operator handoff for the production cluster in this repo. It is intended to be enough context for a future session to operate, validate, and debug the cluster without rediscovering the architecture.

## Current Intended Architecture

### Nodes

- `192.168.178.200`: control plane, `talos-2sm-xkd`
- `192.168.178.201`: worker, `talos-z8c-je7`
- `192.168.178.202`: worker, `talos-3nt-pq2`
- `192.168.178.203`: worker, `talos-w45-5vh`

### Responsibilities

- `200`: single control plane, no Longhorn disk scheduling
- `201`: NVMe performance-secondary storage
- `202`: NVMe performance-primary storage, preferred for Nextcloud and Immich app workloads
- `203`: HDD capacity and backup storage, preferred for Jellyfin and MinIO backup storage

### GitOps Entry Points

- cluster orchestration: [clusters/production/infrastructure.yaml](/home/hannes/gh/passercluster/clusters/production/infrastructure.yaml)
- app orchestration: [clusters/production/apps.yaml](/home/hannes/gh/passercluster/clusters/production/apps.yaml)
- infra controllers: [infrastructure/controllers/production/kustomization.yaml](/home/hannes/gh/passercluster/infrastructure/controllers/production/kustomization.yaml)
- infra configs: [infrastructure/configs/production/kustomization.yaml](/home/hannes/gh/passercluster/infrastructure/configs/production/kustomization.yaml)
- production app overlay: [apps/production/kustomization.yaml](/home/hannes/gh/passercluster/apps/production/kustomization.yaml)

## Non-Negotiable Assumptions

These must be true for the cluster to work.

1. `192.168.178.200` is the Kubernetes and Talos control-plane endpoint.
2. MetalLB owns `192.168.178.240-192.168.178.250`, and this block stays outside DHCP.
3. Envoy Gateway owns `192.168.178.240`.
4. CoreDNS owns `192.168.178.241`.
5. LAN DNS resolves `*.passer.lan` through the cluster DNS path.
6. Flux decrypts SOPS secrets using `flux-system/sops-age`.
7. Longhorn is the storage backend for all stateful apps and backups.

## Bring-Up Order

Do not skip the order.

1. Talos control plane healthy
2. Kubernetes API reachable
3. Flux controllers healthy
4. infra-controllers reconciled
5. infra-configs reconciled
6. apps reconciled
7. Velero and MinIO healthy

## Golden Validation Sequence

Run these in order after any outage or setup work.

### 1. Control Plane

```bash
ping -c1 192.168.178.200
timeout 2 bash -c 'cat < /dev/null > /dev/tcp/192.168.178.200/50000' && echo talos-open || echo talos-closed
timeout 2 bash -c 'cat < /dev/null > /dev/tcp/192.168.178.200/6443' && echo kube-open || echo kube-closed

cd ~/gh/passercluster/talos
talosctl version --nodes 192.168.178.200 --endpoints 192.168.178.200 --talosconfig ./talosconfig
talosctl health --nodes 192.168.178.200 --endpoints 192.168.178.200 --talosconfig ./talosconfig
```

If kubeconfig needs refresh:

```bash
cp ~/.kube/config ~/.kube/config.backup-$(date +%F-%H%M%S)
talosctl kubeconfig --nodes 192.168.178.200 --endpoints 192.168.178.200 --talosconfig ./talosconfig
```

### 2. Kubernetes And Flux

```bash
kubectl get nodes -o wide
kubectl get pods -n flux-system
flux get sources all -A
flux get kustomizations -A
flux get helmreleases -A
kubectl get secret -n flux-system sops-age
```

Expected:

- all four nodes `Ready`
- `infra-controllers`, `infra-configs`, and `apps` `Ready`
- no SOPS decryption failures

### 3. Infra Controllers

```bash
kubectl get pods -n cert-manager
kubectl get pods -n cnpg-system
kubectl get pods -n envoy-gateway-system
kubectl get pods -n homelab-dns
kubectl get pods -n external-dns
kubectl get pods -n metallb-system
kubectl get pods -n longhorn-system
```

### 4. Network, DNS, TLS

```bash
kubectl get svc -A | grep LoadBalancer
kubectl get gateway -n envoy-gateway-system
kubectl get gatewayclass
kubectl get clusterissuer
kubectl get certificate -A
kubectl get httproute -A
kubectl get svc -n homelab-dns homelab-coredns
kubectl get svc -n external-dns external-dns-etcd
kubectl logs -n external-dns deploy/external-dns --tail=100
```

Expected:

- Envoy service on `192.168.178.240`
- CoreDNS service on `192.168.178.241`
- `Gateway` programmed
- `selfsigned-bootstrap` and `selfsigned-issuer` usable
- `wildcard-passer.lan-tls` present in `envoy-gateway-system`

### 5. Storage

```bash
kubectl get storageclass
kubectl get nodes --show-labels
kubectl get nodes.longhorn.io -n longhorn-system
kubectl get volumes.longhorn.io -n longhorn-system
kubectl get recurringjobs.longhorn.io -n longhorn-system
kubectl get pvc -A
```

Expected:

- Longhorn scheduling disabled on `200`
- Longhorn disks present on `201`, `202`, `203`
- no pending PVCs for production workloads

### 6. Applications

```bash
kubectl get pods -n nextcloud
kubectl get pods -n immich
kubectl get pods -n jellyfin
kubectl get pods -n vaultwarden
kubectl get pods -n paperless-ngx
kubectl get pods -n podinfo
```

### 7. Backup Stack

```bash
kubectl get pods -n velero
kubectl get pvc -n velero
kubectl get jobs -n velero
kubectl get schedules.velero.io -n velero
kubectl logs -n velero deploy/velero --tail=100
```

## Service Map

### Core Infrastructure

- cert-manager: internal PKI and wildcard service certs
- Envoy Gateway: HTTP/HTTPS ingress
- MetalLB: LAN LoadBalancer IP assignment
- CoreDNS: authoritative DNS for `passer.lan`
- ExternalDNS: writes `HTTPRoute`-derived DNS records into CoreDNS etcd
- Longhorn: storage backend
- CloudNativePG: PostgreSQL operator for Immich
- Velero + MinIO: backups

### App Exposure Model

This cluster is designed around:

- Gateway API `HTTPRoute`
- Envoy Gateway
- internal `.lan` certificates from `selfsigned-issuer`

This is explicitly reinforced by [infrastructure/controllers/production/external-dns.yaml](/home/hannes/gh/passercluster/infrastructure/controllers/production/external-dns.yaml), which watches `gateway-httproute` sources and states that the cluster exposes applications with Gateway API, not Ingress.

## DNS And TLS Model

### MetalLB

- pool: `192.168.178.240-192.168.178.250`
- advertisement: L2

### Envoy

- LoadBalancer IP: `192.168.178.240`
- wildcard HTTPS listener for `*.passer.lan`

### CoreDNS

- LoadBalancer IP: `192.168.178.241`
- serves `passer.lan`
- reads records from in-cluster etcd at `http://10.97.78.53:2379`

### ExternalDNS

- source types: `gateway-httproute`, `service`
- domain filter: `passer.lan`

### cert-manager

- bootstrap CA issuer: `selfsigned-bootstrap`
- operational issuer: `selfsigned-issuer`
- public `letsencrypt` issuer exists only as reference and is not the normal path for `.lan`

## Storage Model

### Longhorn Node Intent

- `200`: `storage.passercluster.io/longhorn=disabled`
- `201`: performance-secondary NVMe
- `202`: performance-primary NVMe
- `203`: capacity, backup, media HDD

### Storage Classes In Repo

- `longhorn-nvme-201`
- `longhorn-nvme-202`
- `longhorn-media`
- `longhorn-backup`
- `longhorn-nextcloud-fast`
- `longhorn-immich-fast`
- `longhorn-jellyfin`

Longhorn chart config sets `defaultClass: false`, so the cluster should not be treated as if a generic default PVC class will always exist.

## Per-App Requirements

### Nextcloud

- secrets:
  - `nextcloud-credentials`
  - `nextcloud-db`
- hostname: `nextcloud.passer.lan`
- app data on `longhorn-nvme-202`
- MariaDB data on `longhorn-nvme-202`
- node overlay prefers `talos-3nt-pq2`

Checks:

```bash
kubectl get secret -n nextcloud
kubectl get pvc -n nextcloud
kubectl get pods -n nextcloud -o wide
kubectl get httproute -n nextcloud
```

### Immich

- secret: `immich-db`
- CNPG cluster: `immich-postgres`
- library PVC on `longhorn-nvme-202`
- app overlay prefers node `talos-3nt-pq2`
- CNPG storage is on `longhorn-nvme-201`

Checks:

```bash
kubectl get secret -n immich
kubectl get cluster.postgresql.cnpg.io -n immich
kubectl get pvc -n immich
kubectl get pods -n immich -o wide
kubectl get httproute -n immich
```

### Jellyfin

- hostname: `jellyfin.passer.lan`
- pod scheduling prefers nodes with `storage-tier=capacity`
- media PVC on `longhorn-jellyfin`
- config PVC currently references generic `longhorn`

Checks:

```bash
kubectl get pvc -n jellyfin
kubectl get pods -n jellyfin -o wide
kubectl get httproute -n jellyfin
```

### Vaultwarden

- hostname: `vaultwarden.passer.lan`
- data PVC currently references generic `longhorn`

Checks:

```bash
kubectl get pvc -n vaultwarden
kubectl get pods -n vaultwarden
kubectl get httproute -n vaultwarden
```

### Paperless-ngx

- secret: `paperless-ngx-secret`
- chart-managed PostgreSQL and Redis
- four PVCs on `longhorn-immich-fast`
- app URL: `https://paperless.passer.lan`

Checks:

```bash
kubectl get secret -n paperless-ngx
kubectl get pvc -n paperless-ngx
kubectl get pods -n paperless-ngx
kubectl get httproute -n paperless-ngx
kubectl get ingress -n paperless-ngx
```

### Podinfo

- hostname: `podinfo.passer.lan`
- chart handles route exposure

Checks:

```bash
kubectl get pods -n podinfo
kubectl get httproute -n podinfo
```

## Setup Inconsistencies

These are the concrete inconsistencies currently visible in the repo and should be treated as follow-up work.

### 1. Paperless Uses Ingress In A Gateway-Based Cluster

Conflict:

- base Paperless defines an `HTTPRoute`: [apps/base/paperless-ngx/httproute.yaml](/home/hannes/gh/passercluster/apps/base/paperless-ngx/httproute.yaml)
- production overlay enables chart `Ingress` with `cert-manager.io/cluster-issuer: letsencrypt`: [apps/production/paperless-ngx-values.yaml](/home/hannes/gh/passercluster/apps/production/paperless-ngx-values.yaml)
- cluster DNS automation is built around `gateway-httproute`, not Ingress
- `.lan` names are intended to use internal `selfsigned-issuer`, not public ACME

Operational conclusion:

- Paperless should be brought back into the same pattern as the rest of the cluster: `HTTPRoute` plus internal `selfsigned-issuer`
- the production Ingress customization is inconsistent with the repo’s actual ingress model

### 2. Generic `longhorn` Class Is Referenced Despite `defaultClass: false`

Conflict:

- Longhorn chart config disables default class behavior in [infrastructure/controllers/production/longhorn.yaml](/home/hannes/gh/passercluster/infrastructure/controllers/production/longhorn.yaml)
- Jellyfin config PVC uses `storageClass: longhorn`: [apps/base/jellyfin/release.yaml](/home/hannes/gh/passercluster/apps/base/jellyfin/release.yaml)
- Vaultwarden data uses `class: longhorn`: [apps/base/vaultwarden/release.yaml](/home/hannes/gh/passercluster/apps/base/vaultwarden/release.yaml)

Operational conclusion:

- either verify that a `longhorn` storage class is intentionally present and stable, or
- change these workloads to explicit repo-owned storage classes

Until that is resolved, fresh installs may behave differently from an already-running cluster.

### 3. Paperless Secret Is Stored In Plaintext

The file [apps/base/paperless-ngx/paperless-ngx.secret.yaml](/home/hannes/gh/passercluster/apps/base/paperless-ngx/paperless-ngx.secret.yaml) currently contains plaintext credentials and secret key material, unlike the SOPS-encrypted secrets used elsewhere.

Operational conclusion:

- this should be encrypted with SOPS and reconciled through the same decryption path as the other app secrets

## Fast Failure Triage

Use this sequence when something is broken.

### If `kubectl` Fails

1. test `192.168.178.200:6443`
2. test `192.168.178.200:50000`
3. run `talosctl health`
4. back up and refresh kubeconfig only after Talos access works

### If DNS Fails

1. verify `homelab-coredns` has `192.168.178.241`
2. verify `external-dns` pod is healthy
3. verify `HTTPRoute` exists for the hostname
4. check Pi-hole forwarding or local records

### If HTTPS Fails

1. verify `Gateway` listener is programmed
2. verify wildcard secret exists
3. verify client trust for `homelab-root-ca`

### If PVCs Stay Pending

1. inspect storage class name
2. verify Longhorn node labels and disk tags
3. verify enough free space exists on the intended node/disk

### If Apps Reconcile But Are Unreachable

1. confirm pods are `Running`
2. confirm service exists
3. confirm `HTTPRoute` exists
4. confirm ExternalDNS created DNS record path
5. confirm Envoy listener and backend route status

## Safe Commands

### Cluster

```bash
kubectl get nodes -o wide
kubectl get pods -A
flux get kustomizations -A
flux get helmreleases -A
```

### DNS And Ingress

```bash
kubectl get gateway -n envoy-gateway-system
kubectl get httproute -A
kubectl get svc -n envoy-gateway-system
kubectl get svc -n homelab-dns
kubectl logs -n external-dns deploy/external-dns --tail=100
nslookup nextcloud.passer.lan
nslookup immich.passer.lan
```

### Storage

```bash
kubectl get storageclass
kubectl get pvc -A
kubectl get nodes.longhorn.io -n longhorn-system
kubectl get recurringjobs.longhorn.io -n longhorn-system
```

### Apps

```bash
curl -kI https://nextcloud.passer.lan
curl -kI https://immich.passer.lan
curl -kI https://jellyfin.passer.lan
curl -kI https://vaultwarden.passer.lan
curl -kI https://podinfo.passer.lan
```

## Things Not To Do

- do not wipe or reset Talos nodes unless explicitly doing disaster recovery
- do not reinstall the control plane to solve an ordinary node outage
- do not overwrite `secrets.yaml`
- do not regenerate kubeconfig before Talos control-plane access is working
- do not assume old time-skew values are still valid after a node rotates Talos API certs
- do not put MetalLB addresses inside the DHCP pool
- do not mix Ingress and Gateway API casually in this cluster

## End State Checklist

The cluster is healthy only when all of the following are true:

1. `talosctl health` passes against `192.168.178.200`
2. `kubectl get nodes` shows all four nodes `Ready`
3. Flux `infra-controllers`, `infra-configs`, and `apps` are `Ready`
4. Envoy owns `192.168.178.240`
5. CoreDNS owns `192.168.178.241`
6. `*.passer.lan` resolves on LAN clients
7. wildcard/internal certs are present and trusted where required
8. all production PVCs are `Bound`
9. app pods are `Running`
10. Velero and Longhorn backup jobs are healthy

## Next Session Prompt

Use this as the starting brief in the next session:

```text
You are operating the repo ~/gh/passercluster.

Read /home/hannes/gh/passercluster/CLUSTER-SETUP.md first and treat it as the current operator runbook.
If the task involves control-plane recovery, also read /home/hannes/gh/passercluster/talos/CONTROL-PLANE-FIX.md.

Important current cluster facts:
- single control-plane node: 192.168.178.200 / talos-2sm-xkd
- workers: 201 talos-z8c-je7, 202 talos-3nt-pq2, 203 talos-w45-5vh
- MetalLB pool: 192.168.178.240-192.168.178.250
- Envoy Gateway LB IP: 192.168.178.240
- CoreDNS LB IP: 192.168.178.241
- LAN domain: passer.lan
- routing model is Gateway API HTTPRoute, not Ingress
- Longhorn is the storage backend

Known repo inconsistencies to keep in mind:
- Paperless production overlay enables Ingress with letsencrypt, but the cluster is built around HTTPRoute plus selfsigned-issuer for .lan
- Jellyfin and Vaultwarden still reference generic longhorn storage instead of explicit repo-owned storage classes
- apps/base/paperless-ngx/paperless-ngx.secret.yaml contains plaintext secret material and should be migrated to SOPS

When debugging, validate in this order:
1. Talos/API reachability on 192.168.178.200
2. Flux health
3. infra-controllers
4. infra-configs
5. DNS/Gateway/TLS
6. Longhorn/PVCs
7. apps
8. Velero/MinIO backups
```
