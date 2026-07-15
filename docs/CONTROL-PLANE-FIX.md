# Control Plane Recovery

## Summary

The cluster was down because the single control-plane node at `192.168.178.200` was offline on the LAN.

This made:

- `kubectl` fail because `~/.kube/config` pointed at `https://192.168.178.200:6443`
- the Kubernetes API unreachable on `:6443`
- the Talos API unreachable on `:50000`

The problem was not caused by the regenerated local `talosconfig`, the Talos CA, or `secrets.yaml`.

## Observed Symptoms

- `kubectl` failed with `dial tcp 192.168.178.200:6443: connect: no route to host`
- `192.168.178.200` did not answer ping
- `192.168.178.200:50000` and `192.168.178.200:6443` were closed/unreachable
- workers `201`, `202`, and `203` were visible to Talos, but no control-plane member was reachable
- `203` was reachable on the Talos API, but its server certificate was expired

## Important Findings

### Node Roles

- `passer-cp-01.yaml`: control plane
- `passer-w-01.yaml`: worker
- `passer-w-02.yaml`: worker
- `passer-w-03.yaml`: worker

### Config State

The canonical cluster endpoint was still configured as `192.168.178.200:6443` in:

- `talos/passer-cp-01.yaml`
- `talos/passer-w-01.yaml`
- `talos/passer-w-02.yaml`
- `talos/passer-w-03.yaml`
- `~/.kube/config`

The active `talos/talosconfig` did **not** hardcode endpoints. Old expired Talos configs did.

## Root Cause

The control-plane machine at `192.168.178.200` was offline or stuck and absent from the network.

Because this cluster has a single control-plane node, losing `200` meant:

- no reachable Talos API on the control plane
- no reachable Kubernetes API
- no functioning `kubectl`

The worker nodes were still present, but they could not restore Kubernetes access on their own.

## Recovery Process

### 1. Verified repo and config state

We confirmed:

- `192.168.178.200` was still the configured control-plane endpoint
- the local regenerated `talosconfig` was valid
- `secrets.yaml` did not need modification

### 2. Used a temporary laptop time workaround on worker `203`

Node `203` still answered on `:50000`, but its Talos API server cert had expired.

By temporarily setting the laptop clock to a time before that certificate expiry, we could query Talos safely enough to inspect membership:

```bash
sudo timedatectl set-ntp false
sudo timedatectl set-time '2026-06-01 04:30:00'

talosctl get members \
  --nodes 192.168.178.203 \
  --endpoints 192.168.178.203 \
  --talosconfig ./talosconfig

sudo timedatectl set-ntp true
```

That showed only worker members:

- `192.168.178.201`
- `192.168.178.202`
- `192.168.178.203`

No control-plane member was reachable at that point.

### 3. Confirmed node `200` itself was the real issue

Direct checks from the laptop showed:

- `ping 192.168.178.200` failed
- neighbor resolution for `192.168.178.200` failed
- no Talos API on `192.168.178.200:50000`
- no Kubernetes API on `192.168.178.200:6443`

That narrowed the failure to the machine or its immediate network presence, not the local Talos client config.

### 4. Performed a manual reboot of node `200`

A manual reboot of the control-plane machine was the correct recovery action.

We explicitly avoided:

- reinstalling Talos
- reapplying machine configs
- resetting the node
- wiping disks
- overwriting `secrets.yaml`

### 5. Re-checked node `200` after reboot

After reboot:

- `192.168.178.200` responded to ping again
- `192.168.178.200:50000` opened
- `192.168.178.200:6443` was initially still closed, then later opened

The control-plane Talos API server certificate on `200` had also rotated to a fresh cert:

- `notBefore=Jun 23 10:24:56 2026 GMT`
- `notAfter=Jun 24 10:24:56 2026 GMT`

That meant the earlier time-skew workaround was no longer valid for `200`; access had to use the real current time.

### 6. Connected to the control plane with real current time

With normal time restored:

```bash
talosctl version \
  --nodes 192.168.178.200 \
  --endpoints 192.168.178.200 \
  --talosconfig ./talosconfig

talosctl get members \
  --nodes 192.168.178.200 \
  --endpoints 192.168.178.200 \
  --talosconfig ./talosconfig

talosctl health \
  --nodes 192.168.178.200 \
  --endpoints 192.168.178.200 \
  --talosconfig ./talosconfig
```

This confirmed:

- `192.168.178.200` was the control-plane node
- all four nodes were present in membership again
- cluster health checks passed

### 7. Verified core control-plane services

The following Talos services on `200` were healthy:

- `etcd`
- `kubelet`
- `apid`

The Kubernetes API port on `192.168.178.200:6443` was open again.

## Final State

The cluster was restored once the control-plane node came back after a manual reboot.

Healthy end state:

- `talosctl` could connect to `192.168.178.200` using the real current time
- Talos membership showed the control plane and all workers
- `talosctl health` passed
- `192.168.178.200:6443` was open again
- kubeconfig refresh could safely proceed afterward

## Safe Commands Used

### Reachability

```bash
for ip in 192.168.178.{200..203}; do
  echo "=== $ip ==="
  ping -c1 -W1 "$ip" >/dev/null && echo "ping ok" || echo "ping fail"
  timeout 2 bash -c "cat < /dev/null > /dev/tcp/$ip/50000" 2>/dev/null && echo "talos api open" || echo "talos api closed"
  timeout 2 bash -c "cat < /dev/null > /dev/tcp/$ip/6443" 2>/dev/null && echo "kube api open" || echo "kube api closed"
done
```

### Talos server cert inspection

```bash
echo | openssl s_client -connect 192.168.178.200:50000 -showcerts 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

### Kubeconfig backup before refresh

```bash
cp ~/.kube/config ~/.kube/config.backup-$(date +%F-%H%M%S)
```

### Kubeconfig refresh after control-plane recovery

```bash
talosctl kubeconfig \
  --nodes 192.168.178.200 \
  --endpoints 192.168.178.200 \
  --talosconfig ./talosconfig
```

## What Not To Do

These actions were intentionally avoided during recovery:

- do not reset nodes
- do not wipe disks
- do not overwrite `secrets.yaml`
- do not reinstall Talos just because the control plane is unreachable
- do not reapply machine configs unless there is a confirmed config problem
- do not edit `~/.kube/config` before backing it up
- do not regenerate kubeconfig before Talos control-plane access works

## Operational Lessons

1. If only workers are reachable, inspect Talos membership before changing configs.
2. If the configured control-plane IP is absent from the network, treat it as a node-availability problem first.
3. Temporary laptop clock skew is useful only for expired Talos API certs and only for nodes whose cert validity window matches that skew.
4. A fresh Talos API cert on reboot means the laptop must return to real current time.
5. Rebooting the actual control-plane node was sufficient; reinstalling Talos would have added unnecessary risk.
