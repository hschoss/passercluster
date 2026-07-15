# Talos Node Recovery Runbook — passercluster

## Cluster Overview

| Role | Hostname | IP | Disk |
|---|---|---|---|
| Control Plane | passer-cp-01 | 192.168.178.200 | NVMe (`type: nvme`) |
| Worker | passer-w-01 | 192.168.178.201 | NVMe (`type: nvme`) |
| Worker | passer-w-02 | 192.168.178.202 | NVMe (`type: nvme`) |
| Worker | passer-w-03 | 192.168.178.203 | SATA/USB (`type: ssd`) |

**Control plane endpoint:** `https://192.168.178.200:6443`  
**Talos API port:** `50000`  
**talosconfig:** `talos/talosconfig` (endpoint pre-filled to `192.168.178.200`)

---

## What Changed vs. the Old Configs

### 1. Static hostnames
All four configs now have an explicit `HostnameConfig` block:
```yaml
apiVersion: v1alpha1
kind: HostnameConfig
hostname: passer-w-01   # static, never drifts
```
Previously `auto: stable` was used, which regenerates a hostname from hardware IDs after a board swap, leaving ghost node objects in the cluster.

### 2. `diskSelector` instead of hardcoded `/dev/...`
Old: `disk: /dev/nvme0n1` or `disk: /dev/sdh`  
New: `diskSelector: { type: nvme }` (workers 01/02) and `diskSelector: { type: ssd }` (worker 03)  
If a disk re-enumerates as `nvme1n1` after hardware maintenance, the selector still finds it. The hardcoded path would silently target the wrong device or fail.

### 3. `talosconfig` endpoint pre-filled
Old `talosconfig` had `endpoints: []` — you had to pass `--nodes` and `--endpoints` on every command.  
New `talosconfig` defaults to `192.168.178.200` so bare `talosctl get members` works.

---

## Step 0 — Before Anything: Verify Cluster Health

Run this reachability check first. It tells you immediately what is alive:

```bash
for ip in 192.168.178.{200..203}; do
  printf "=== %-18s " "$ip"
  ping -c1 -W1 "$ip" >/dev/null 2>&1 && printf "ping OK  " || printf "ping FAIL"
  timeout 2 bash -c "cat < /dev/null > /dev/tcp/$ip/50000" 2>/dev/null \
    && printf "  talos OPEN  " || printf "  talos CLOSED"
  timeout 2 bash -c "cat < /dev/null > /dev/tcp/$ip/6443" 2>/dev/null \
    && printf "  kube OPEN" || printf "  kube CLOSED"
  echo
done
```

Expected healthy output:
```
=== 192.168.178.200   ping OK    talos OPEN    kube OPEN
=== 192.168.178.201   ping OK    talos OPEN    kube CLOSED
=== 192.168.178.202   ping OK    talos OPEN    kube CLOSED
=== 192.168.178.203   ping OK    talos OPEN    kube CLOSED
```

---

## Scenario A — Worker Is Down (most common)

Workers are stateless from Talos' perspective. Recovery is ~3 minutes.

### A1 — Worker rebooted itself and came back clean

Nothing to do. Check it rejoined:

```bash
talosctl get members --talosconfig talos/talosconfig
kubectl get nodes
```

### A2 — Worker needs config reapplied (e.g. after reinstall)

Boot the node from the Talos ISO or netboot image, then:

```bash
# Replace W with 01, 02, or 03 and IP with the node's IP
NODE_IP=192.168.178.201
talosctl apply-config \
  --insecure \
  --nodes "$NODE_IP" \
  --file talos/passer-w-01.yaml
```

`--insecure` is only needed before the node has joined the cluster and received its certificate.
Once it is joined, omit `--insecure`:

```bash
talosctl apply-config \
  --nodes 192.168.178.201 \
  --talosconfig talos/talosconfig \
  --file talos/passer-w-01.yaml
```

### A3 — Verify after apply

```bash
# Watch node come up (Ctrl+C when Ready)
watch -n2 kubectl get node passer-w-01

# Confirm Talos services are healthy
talosctl service \
  --nodes 192.168.178.201 \
  --talosconfig talos/talosconfig

# Full cluster health
talosctl health \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig
```

---

## Scenario B — Control Plane Is Down

This is the critical path. Without the control plane, `kubectl` and Flux stop working.

### B1 — Try a simple reboot first

Physically reboot the machine or power-cycle it. The control plane holds etcd state on disk — a clean reboot brings everything back. **This is what fixed the last outage.**

After reboot, wait 60–90 seconds then re-run the Step 0 check.

### B2 — If Talos API responds but Kubernetes API doesn't

```bash
talosctl version \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig

# Check what services are running
talosctl service \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig

# Look at etcd specifically
talosctl service etcd \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig

# Fetch logs if a service is stuck
talosctl logs etcd \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig
```

### B3 — Reapply config to control plane (non-destructive)

This is safe as long as `wipe: false` is set (it is):

```bash
talosctl apply-config \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig \
  --file talos/passer-cp-01.yaml
```

This will trigger a controlled reboot if there are changes, or a no-op if config is identical.

### B4 — Refresh kubeconfig after control plane is back

```bash
cp ~/.kube/config ~/.kube/config.backup-$(date +%F-%H%M%S)

talosctl kubeconfig \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig
```

### B5 — Inspect Talos API certificate expiry

The Talos API cert on a freshly booted node is short-lived (~24h). If you get TLS errors:

```bash
echo | openssl s_client -connect 192.168.178.200:50000 -showcerts 2>/dev/null \
  | openssl x509 -noout -dates
```

If expired: reboot the node. Talos rotates the API cert on every boot.

---

## Scenario C — Talos API Cert Expired on Worker (emergency access)

**Only use this if you have no other access path.** This involves temporarily skewing the laptop clock.

```bash
# Check cert validity window on the target node
echo | openssl s_client -connect 192.168.178.203:50000 -showcerts 2>/dev/null \
  | openssl x509 -noout -dates

# Set clock to a time inside the cert's validity window (example: June 1)
sudo timedatectl set-ntp false
sudo timedatectl set-time '2026-06-01 04:30:00'

# Now query the node
talosctl get members \
  --nodes 192.168.178.203 \
  --endpoints 192.168.178.203 \
  --talosconfig talos/talosconfig

# Restore time immediately after
sudo timedatectl set-ntp true
```

---

## Testing the New Configuration (Dry Run)

Before applying the improved configs to a live node, validate them:

### Test 1 — Validate YAML structure

```bash
# Install talosctl if needed: https://github.com/siderolabs/talos/releases
# Validate each config file
for f in talos/passer-cp-01.yaml talos/passer-w-01.yaml talos/passer-w-02.yaml talos/passer-w-03.yaml; do
  echo "=== $f ==="
  talosctl validate --mode metal --config "$f" && echo "OK" || echo "FAILED"
done
```

### Test 2 — Dry-run apply against a live node (no actual change)

```bash
# Check what would change without applying it
talosctl apply-config \
  --nodes 192.168.178.201 \
  --talosconfig talos/talosconfig \
  --file talos/passer-w-01.yaml \
  --dry-run
```

Look for lines starting with `+` (additions) or `-` (removals). A clean dry-run on an already-configured node should show only the changes between old and new config.

### Test 3 — Verify hostname config is correct

After applying to a node, check the hostname actually set:

```bash
talosctl get hostname \
  --nodes 192.168.178.201 \
  --talosconfig talos/talosconfig
```

Expected: `passer-w-01`

### Test 4 — Verify diskSelector resolved correctly

```bash
talosctl get disks \
  --nodes 192.168.178.201 \
  --talosconfig talos/talosconfig
```

The disk matching your selector should be listed. Cross-check with:

```bash
talosctl get installedextensions \
  --nodes 192.168.178.201 \
  --talosconfig talos/talosconfig
```

### Test 5 — Confirm Longhorn mount works

```bash
talosctl read /proc/mounts \
  --nodes 192.168.178.201 \
  --talosconfig talos/talosconfig \
  | grep longhorn
```

Expected: a bind mount entry for `/var/lib/longhorn`.

### Test 6 — Full cluster health after any change

```bash
talosctl health \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig
```

All checks should pass. If any fail, run:

```bash
talosctl dmesg --nodes 192.168.178.200 --talosconfig talos/talosconfig | tail -50
talosctl logs kubelet --nodes 192.168.178.200 --talosconfig talos/talosconfig | tail -50
```

---

## Rolling Out the New Config to All Nodes

Do one node at a time. Workers first, control plane last.

```bash
# Worker 01
talosctl apply-config \
  --nodes 192.168.178.201 \
  --talosconfig talos/talosconfig \
  --file talos/passer-w-01.yaml
sleep 60
kubectl wait --for=condition=Ready node/passer-w-01 --timeout=120s

# Worker 02
talosctl apply-config \
  --nodes 192.168.178.202 \
  --talosconfig talos/talosconfig \
  --file talos/passer-w-02.yaml
sleep 60
kubectl wait --for=condition=Ready node/passer-w-02 --timeout=120s

# Worker 03
talosctl apply-config \
  --nodes 192.168.178.203 \
  --talosconfig talos/talosconfig \
  --file talos/passer-w-03.yaml
sleep 60
kubectl wait --for=condition=Ready node/passer-w-03 --timeout=120s

# Control plane — last, because this restarts the Kubernetes API briefly
talosctl apply-config \
  --nodes 192.168.178.200 \
  --talosconfig talos/talosconfig \
  --file talos/passer-cp-01.yaml
sleep 90
kubectl wait --for=condition=Ready node/passer-cp-01 --timeout=180s

# Final state check
kubectl get nodes -o wide
talosctl health --nodes 192.168.178.200 --talosconfig talos/talosconfig
```

---

## Quick Reference Card

```
# Check who is alive
for ip in 192.168.178.{200..203}; do ping -c1 -W1 $ip >/dev/null && echo "$ip up" || echo "$ip DOWN"; done

# Show cluster members
talosctl get members --talosconfig talos/talosconfig

# Show all nodes
kubectl get nodes -o wide

# Apply worker config
talosctl apply-config --nodes <IP> --talosconfig talos/talosconfig --file talos/passer-w-0X.yaml

# Apply CP config
talosctl apply-config --nodes 192.168.178.200 --talosconfig talos/talosconfig --file talos/passer-cp-01.yaml

# Refresh kubeconfig
talosctl kubeconfig --nodes 192.168.178.200 --talosconfig talos/talosconfig

# Health check
talosctl health --nodes 192.168.178.200 --talosconfig talos/talosconfig

# Check Talos API cert expiry
echo | openssl s_client -connect <IP>:50000 2>/dev/null | openssl x509 -noout -dates

# Dry run (safe preview)
talosctl apply-config --nodes <IP> --talosconfig talos/talosconfig --file talos/passer-w-0X.yaml --dry-run
```

---

## What NOT To Do

- **Do not `wipe: true` unless you are intentionally reinstalling** — all data on the disk is lost
- **Do not regenerate `secrets.yaml`** — this would invalidate all existing node certs and require full cluster reinstall
- **Do not overwrite `talosconfig` before backing it up** — you lose the admin cert
- **Do not reapply configs in parallel** — one node at a time, control plane last
- **Do not skip the dry-run** the first time you apply a changed config
