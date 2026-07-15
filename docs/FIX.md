# Talos Recovery Notes

## Findings

- The active client config is valid: `talosconfig` has an admin cert valid from `Jun 23 2026` to `Jun 23 2027`, and its `context` is `passercluster` with empty `endpoints`/`nodes`.
- The recovered copy is the same shape: `recovered-talosconfig/talosconfig` also has empty `endpoints`.
- The expired backups still hardcode `192.168.178.200` in both `endpoints` and `nodes`: `talosconfig.expired-old` and `talosconfig.expired-2026-06-23`.
- The machine configs still point the cluster endpoint at `192.168.178.200`:
  - `passer-cp-01.yaml`
  - `passer-w-01.yaml`
  - `passer-w-02.yaml`
  - `passer-w-03.yaml`
- Current reachability check:
  - `192.168.178.200`: unreachable
  - `192.168.178.201`: ping OK, Talos API closed
  - `192.168.178.202`: ping OK, Talos API closed in the latest local check
  - `192.168.178.203`: ping OK, Talos API open, server cert expired

## Minimal Safe Recovery Plan

1. Do not edit `talosconfig` yet.
2. Use a temporary clock skew only long enough to talk to the expired server cert on `203`.
3. Query `203` first, then use Talos membership to identify the real control-plane node.
4. If you later want to persist endpoint defaults in `talosconfig`, back it up first.
5. Do not overwrite `secrets.yaml`.

## Exact Commands

### Verify node certificate and port state

```bash
echo | openssl s_client -connect 192.168.178.203:50000 -showcerts 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

timeout 2 bash -c 'cat < /dev/null > /dev/tcp/192.168.178.203/50000' \
  && echo "talos api open" || echo "talos api closed"
```

### Temporarily skew laptop time for `192.168.178.203`

```bash
sudo timedatectl set-ntp false
sudo timedatectl set-time '2026-06-01 04:30:00'
```

### Test Talos against `203`

```bash
talosctl version \
  --nodes 192.168.178.203 \
  --endpoints 192.168.178.203 \
  --talosconfig ./talosconfig

talosctl get members \
  --nodes 192.168.178.203 \
  --endpoints 192.168.178.203 \
  --talosconfig ./talosconfig \
  -o wide
```

### After identifying the control-plane node

```bash
talosctl kubeconfig \
  --nodes <control-plane-ip> \
  --endpoints <control-plane-ip> \
  --talosconfig ./talosconfig

talosctl health \
  --nodes <control-plane-ip> \
  --endpoints <control-plane-ip> \
  --talosconfig ./talosconfig
```

### Restore NTP afterwards

```bash
sudo timedatectl set-ntp true
```

### Optional retry for `192.168.178.202`

Use a time before its cert expiry:

```bash
sudo timedatectl set-ntp false
sudo timedatectl set-time '2026-06-01 12:30:00'
# then repeat talosctl commands against 192.168.178.202
sudo timedatectl set-ntp true
```


## Dashboard Debug

To reach the control-plane path through a live node, start the dashboard against a node that still answers on 50000, then inspect membership and move toward the real control-plane endpoint.

```bash
talosctl dashboard \
  --nodes 192.168.178.203 \
  --endpoints 192.168.178.203 \
  --talosconfig ./talosconfig
```

If the dashboard opens but `192.168.178.200` does not appear, that means 200 is not reachable from Talos right now. In that case, use membership discovery from the live node instead of targeting 200 directly.

```bash
talosctl get members \
  --nodes 192.168.178.203 \
  --endpoints 192.168.178.203 \
  --talosconfig ./talosconfig \
  -o wide
```

If you need to test whether 200 itself is the issue, keep the temporary skew active and check the Talos API and cert directly:

```bash
echo | openssl s_client -connect 192.168.178.200:50000 -showcerts 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates

for ip in 192.168.178.{200..203}; do
  echo "=== $ip ==="
  ping -c1 -W1 "$ip" >/dev/null && echo "ping ok" || echo "ping fail"
  timeout 2 bash -c "cat < /dev/null > /dev/tcp/$ip/50000" 2>/dev/null \
    && echo "talos api open" || echo "talos api closed"
done
```

If `192.168.178.200` is expected to be the control-plane endpoint but still does not answer on 50000, the failure is below `talosctl` and you should continue from a live node to discover the actual control-plane member.
