# Tutorial: Cluster health & dashboards from schlaeptop

Everything you can check about the passercluster from your laptop, without
touching the hardware. Grouped by layer: Talos (bare metal) → Kubernetes
→ Flux → Longhorn → apps.

---

## 0. One-time setup

```bash
# Tailscale must be up — schlaeptop reaches the LAN via the `passer` subnet router.
tailscale status | grep passer                   # expect "active"

# Env for every talosctl / kubectl / flux call in this tutorial.
export TALOSCONFIG="$HOME/gh/passercluster/talos/talosconfig"
export KUBECONFIG="$HOME/gh/passercluster/talos/kubeconfig"

# Use the version-matched talos client for the current cluster (v1.13.7).
# The system-wide `/usr/bin/talosctl` is v1.14.4; the matched one lives at:
alias talosctl="$HOME/.local/bin/talosctl-1.13.7"
```

Put the three `export`s plus the alias in your shell rc so you don't type
them every time, or run `direnv allow` with an `.envrc` in `~/gh/passercluster/`.

**Node IPs are static** (DHCP reservations):

| Node | IP | Role |
|---|---|---|
| passer-cp-01 | 192.168.178.200 | control plane |
| passer-w-01 | 192.168.178.201 | worker |
| passer-w-02 | 192.168.178.202 | worker |
| passer-w-03 | 192.168.178.203 | worker |

---

## 1. Talos — bare-metal view

### 1.1 Interactive TUI dashboard

The best live view of a single node:

```bash
talosctl -n 192.168.178.200 dashboard
```

Shows CPU, memory, disk I/O, network per interface, kernel logs, pod
activity in real time. Scroll with arrow keys, `q` quits. Switch node
with `--nodes` or `-n`.

### 1.2 One-shot health check

```bash
talosctl health                                   # whole cluster, blocks until ready/timeout
talosctl health --wait-timeout 10s                # don't block long
```

Returns non-zero when etcd / API / kubelet aren't fully up.

### 1.3 Node + hardware inventory

```bash
talosctl -n 192.168.178.202 version               # Talos server version + enabled features
talosctl -n 192.168.178.202 get disks             # all block devices with model, serial, size
talosctl -n 192.168.178.202 get mountstatuses     # mounted filesystems (/var, /var/mnt/*, …)
talosctl -n 192.168.178.202 get members           # Talos discovery service members
talosctl -n 192.168.178.202 get extensions        # Talos extensions (iscsi-tools, …) + schematic id
talosctl -n 192.168.178.202 get addresses         # interfaces + IPs
```

### 1.4 Services (etcd, kubelet, machined, …)

```bash
talosctl -n 192.168.178.200 services              # one-line health per service
talosctl -n 192.168.178.200 service kubelet       # detailed health + recent events for one service
```

### 1.5 Kernel + system logs

```bash
talosctl -n 192.168.178.202 dmesg | tail -200
talosctl -n 192.168.178.202 logs machined
talosctl -n 192.168.178.202 logs kubelet
```

Filter for errors around a specific time:

```bash
talosctl -n 192.168.178.202 dmesg | awk '/2026-10-26T18:5/'  # the I/O storm, as an example
```

### 1.6 etcd (control plane only)

```bash
talosctl -n 192.168.178.200 etcd members          # single-member on this cluster, not HA
talosctl -n 192.168.178.200 etcd status           # DB size, raft index, leader
talosctl -n 192.168.178.200 etcd snapshot ./etcd.$(date -u +%Y%m%dT%H%M%SZ).snapshot
```

The snapshot is the rollback point before any CP-touching change.

---

## 2. Kubernetes — control plane + nodes

### 2.1 Node view

```bash
kubectl get nodes -o wide
kubectl top nodes                                 # CPU + mem (if metrics-server is up)
kubectl describe node passer-w-02 | tail -40      # taints, allocated, events
```

### 2.2 Pod view across the cluster

```bash
kubectl get pods -A -o wide
```

**Only unhealthy pods** (ignore the always-noisy Velero kopia maintain Jobs):

```bash
kubectl get pods -A --no-headers \
  | awk '$4 != "Running" && $4 != "Completed"' \
  | grep -v kopia-maintain
```

**Who's using the most memory right now:**

```bash
kubectl top pods -A --sort-by=memory | head -20
```

### 2.3 Recent events (what just broke)

```bash
kubectl get events -A --sort-by=.lastTimestamp | tail -30
```

### 2.4 Zoom into one namespace

```bash
NS=immich
kubectl -n $NS get all,httproute,cluster.postgresql.cnpg.io,pvc
kubectl -n $NS describe pod $(kubectl -n $NS get pods -o name | head -1)
kubectl -n $NS logs <pod> --tail 100
kubectl -n $NS logs <pod> --previous --tail 100   # last crash
```

### 2.5 CNPG postgres clusters

```bash
kubectl get cluster.postgresql.cnpg.io -A
kubectl -n sonnen describe cluster sonnen-postgres | tail -40
```

### 2.6 CSI / storage attachments

```bash
kubectl get pv,pvc -A | grep -v Bound             # anything not Bound = problem
kubectl get volumeattachments
```

---

## 3. Flux — GitOps reconciliation state

### 3.1 Health one-liner

```bash
flux get all -A
```

### 3.2 Specific layers

```bash
flux get sources git -A
flux get kustomizations -A
flux get helmreleases -A
flux stats -A                                     # count + ready/suspended per resource type
```

### 3.3 Only unhealthy things

```bash
flux get kustomizations -A | awk '$4 == "False"'
flux get helmreleases -A | awk '$4 == "False"'
```

### 3.4 Force a reconcile

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization infra-controllers -n flux-system
flux reconcile kustomization infra-configs -n flux-system
flux reconcile kustomization apps -n flux-system
```

### 3.5 Why is X stuck?

```bash
flux -n flux-system describe kustomization <name>
flux -n <ns> describe helmrelease <name>
kubectl -n flux-system logs -l app=kustomize-controller --tail 100
kubectl -n flux-system logs -l app=helm-controller --tail 100
```

---

## 4. Longhorn — storage dashboard

### 4.1 Web UI

Open in a browser (from the LAN or via Tailscale):

```
https://longhorn.passer.lan
```

Shows nodes + disks + volumes + replicas, with a per-volume rebuild UI.
TLS warning is expected the first time; the cert is the self-signed
`passer-lan-tls`. Trust `secrets/passer-lan.crt` on your daily machines
to silence it.

### 4.2 CLI health check

```bash
scripts/longhorn-health-check.sh                  # compact: nodes + disks + volumes
```

### 4.3 Volume state at the API

```bash
kubectl -n longhorn-system get nodes.longhorn.io
kubectl -n longhorn-system get volumes.longhorn.io \
  -o custom-columns='NAME:.metadata.name,STATE:.status.state,ROBUST:.status.robustness,NODE:.status.ownerID'
```

**Only degraded or faulted volumes:**

```bash
kubectl -n longhorn-system get volumes.longhorn.io -o json \
  | jq -r '.items[] | select(.status.robustness != "healthy") | [.metadata.name, .status.state, .status.robustness] | @tsv'
```

### 4.4 Disk fill

```bash
kubectl -n longhorn-system get nodes.longhorn.io -o json \
  | jq -r '.items[] | .metadata.name as $n | .status.diskStatus | to_entries[]
      | [$n, .key, (.value.storageAvailable/1e9), (.value.storageScheduled/1e9), (.value.storageMaximum/1e9)] | @tsv' \
  | awk 'BEGIN{printf "%-15s %-30s %10s %10s %10s\n","NODE","DISK","AVAIL(GB)","SCHED(GB)","MAX(GB)"} {printf "%-15s %-30s %10.1f %10.1f %10.1f\n",$1,$2,$3,$4,$5}'
```

---

## 5. Service dashboards (apps)

All on `https://<name>.passer.lan`. Pi-hole forwards `*.passer.lan` to
CoreDNS inside the cluster; the Envoy Gateway serves them on
`192.168.178.240`.

| URL | Who it's for |
|---|---|
| `https://passer.lan` | landing page + `/docs/` of this repo |
| `https://longhorn.passer.lan` | storage dashboard (§4.1) |
| `https://auth.passer.lan` | Authentik SSO admin (login `akadmin`) |
| `https://nextcloud.passer.lan` | files + calendar + contacts admin |
| `https://immich.passer.lan` | photos |
| `https://jellyfin.passer.lan` | media |
| `https://paperless.passer.lan` | documents |
| `https://vaultwarden.passer.lan` | password manager |
| `https://podinfo.passer.lan` | smoke-test ("if this is down, DNS or TLS is broken") |
| `https://finance.passer.lan` | Findash (placeholder until the image is built) |

---

## 6. Common "is everything OK?" one-liner

```bash
echo "— talos health —"
talosctl health --wait-timeout 10s 2>&1 | tail
echo
echo "— unhealthy pods —"
kubectl get pods -A --no-headers | awk '$4 != "Running" && $4 != "Completed"' | grep -v kopia-maintain | head
echo
echo "— flux not-ready —"
flux get kustomizations -A | awk 'NR==1 || $4=="False"'
flux get helmreleases -A | awk 'NR==1 || $4=="False"'
echo
echo "— degraded longhorn volumes —"
kubectl -n longhorn-system get volumes.longhorn.io -o json \
  | jq -r '.items[] | select(.status.robustness != "healthy") | [.metadata.name, .status.state, .status.robustness] | @tsv'
```

If every section is empty-ish (only headers), the cluster is healthy.
Anything else — follow the thread into §1–§5 for that specific layer.

---

## 7. Where to look next

- Deep troubleshooting runbook: `docs/TROUBLESHOOTING.md`
- Day-to-day operations checklist: `docs/OPERATIONS.md`
- One-liner reference: `docs/COMMANDS.md`
- Full project brief: `CLAUDE.md`
