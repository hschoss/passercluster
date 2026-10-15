#!/usr/bin/env bash
# Bring the passer Raspberry Pi onto the corvus LAN as a WireGuard client
# so the Kubernetes cluster can reach the corvus Pi (MinIO at .179.2) via
# the FritzBox-to-FritzBox tunnel. The config was handed over as
# ~/wg_config.conf by the admin.
#
# Run on the passer Pi as root (or with sudo).
#
# What it does, in this order:
#   1. apt install wireguard-tools iptables-persistent.
#   2. Rewrites wg_config.conf: AllowedIPs is limited to 192.168.179.0/24
#      and the IPv6 corvus subnet, so the Pi does not get a full-tunnel
#      default route via wg0 (which would kill SSH).
#   3. Installs the config to /etc/wireguard/wg0.conf (mode 600).
#   4. Enables ip_forward (persistent sysctl drop-in).
#   5. Adds an iptables MASQUERADE on wg0 for packets from 192.168.178.0/24
#      and persists it via netfilter-persistent.
#   6. Enables and starts wg-quick@wg0.
#   7. Pings 192.168.179.1 and 192.168.179.2 to verify.
#
# After this script, you still need to add a static route in the
# passer-FritzBox UI: 192.168.179.0/24 via 192.168.178.2.

set -euo pipefail
umask 077

SRC_CONF="/home/vault/wg_config.conf"
DST_CONF="/etc/wireguard/wg0.conf"
LAN_SUBNET="192.168.178.0/24"
CORVUS_V4="192.168.179.0/24"
CORVUS_V6="fd0f:5f3a:8339::/64"

if [[ $EUID -ne 0 ]]; then
  echo "re-exec via sudo"
  exec sudo -E bash "$0" "$@"
fi

echo "[1/7] apt install ..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y wireguard wireguard-tools iptables-persistent

echo "[2/7] narrow AllowedIPs to corvus subnets and drop DNS lines ..."
# Replace the AllowedIPs line to drop 0.0.0.0/0 and ::/0, keep only corvus.
# Strip DNS lines: wg-quick(8) would invoke resolvconf, which is not
# installed on the Pi (and the Pi uses its own DNS, so it does not need the
# corvus DNS from the FritzBox).
tmp="$(mktemp)"
awk -v v4="$CORVUS_V4" -v v6="$CORVUS_V6" '
  /^AllowedIPs[[:space:]]*=/ { print "AllowedIPs = " v4 "," v6; next }
  /^DNS[[:space:]]*=/        { next }
  { print }
' "$SRC_CONF" > "$tmp"

echo "[3/7] install to $DST_CONF ..."
install -m 0600 "$tmp" "$DST_CONF"
rm -f "$tmp"
echo "---- effective wg0 config (keys masked) ----"
sed -E 's/(PrivateKey|PresharedKey|PublicKey)[[:space:]]*=.*/\1 = <masked>/' "$DST_CONF"
echo "--------------------------------------------"

echo "[4/7] enable ip_forward ..."
cat > /etc/sysctl.d/99-wg-forward.conf <<EOF
net.ipv4.ip_forward=1
net.ipv6.conf.all.forwarding=1
EOF
sysctl --system >/dev/null

echo "[5/7] iptables NAT ..."
# Only MASQUERADE traffic from the passer LAN out through wg0.
iptables -t nat -C POSTROUTING -s "$LAN_SUBNET" -o wg0 -j MASQUERADE 2>/dev/null \
  || iptables -t nat -A POSTROUTING -s "$LAN_SUBNET" -o wg0 -j MASQUERADE
# Allow forwarding both ways between eth0 (passer LAN) and wg0 (corvus).
iptables -C FORWARD -i eth0 -o wg0 -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i eth0 -o wg0 -j ACCEPT
iptables -C FORWARD -i wg0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
  || iptables -A FORWARD -i wg0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
netfilter-persistent save

echo "[6/7] systemctl enable --now wg-quick@wg0 ..."
systemctl enable --now wg-quick@wg0.service

echo "[7/7] reachability check ..."
sleep 2
set +e
ping -c 2 -W 2 192.168.179.1 && echo "   corvus-fritz reachable" || echo "   corvus-fritz UNREACHABLE"
ping -c 2 -W 2 192.168.179.2 && echo "   corvus-pi reachable"    || echo "   corvus-pi UNREACHABLE"
set -e

cat <<EOF

Done. Next steps:
  1. In the passer-FritzBox UI (http://fritz.box, "Heimnetz > Netzwerk >
     Netzwerkverbindungen > Statische Routingtabelle"), add:
       Netzwerk:  192.168.179.0
       Maske:     255.255.255.0
       Gateway:   192.168.178.2
     without this route the Kubernetes nodes still cannot reach the corvus Pi.

  2. On the corvus Pi, run scripts/install-minio-on-corvus-pi.sh and paste
     the credentials from its output into the velero-credentials secret.
EOF
