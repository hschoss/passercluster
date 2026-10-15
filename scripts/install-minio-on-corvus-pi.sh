#!/usr/bin/env bash
# Install MinIO as a systemd service on the corvus Raspberry Pi so passer's
# Velero can push backups into the ZFS pool `tank`.
#
# Run on the corvus Pi, as user `vault` or root with sudo. Once the WireGuard
# tunnel from the passer Pi is up and the passer-FritzBox has the static
# route for 192.168.179.0/24, this host is reachable from the cluster at
# 192.168.179.2:9000.
#
# Prerequisites on this Pi:
#   - ZFS pool `tank` imported and healthy (zpool status tank).
#   - User `vault` exists (used only as owner of the data directory).
#   - A working package manager with internet access.
#
# What it does:
#   1. Creates ZFS dataset tank/velero mounted at /tank/velero.
#   2. Downloads the MinIO server binary into /usr/local/bin.
#   3. Writes /etc/default/minio with generated credentials.
#   4. Installs and starts a minio.service listening on 0.0.0.0:9000.
#   5. Creates the "passer-velero" bucket via a tiny mc one-shot.
#   6. Prints the credentials once at the end — paste them into the Flux
#      velero-credentials secret via SOPS on your laptop.

set -euo pipefail

MINIO_DATA=/tank/velero
MINIO_USER=vault
MINIO_LISTEN_ADDR="0.0.0.0:9000"
MINIO_CONSOLE_ADDR="0.0.0.0:9001"
BUCKET=passer-velero

need_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "re-exec via sudo"
    exec sudo -E bash "$0" "$@"
  fi
}
need_root "$@"

echo "[1/6] zfs dataset tank/velero ..."
if ! zfs list tank/velero >/dev/null 2>&1; then
  zfs create -o mountpoint="$MINIO_DATA" -o compression=lz4 -o atime=off tank/velero
fi
chown -R "$MINIO_USER":"$MINIO_USER" "$MINIO_DATA"

echo "[2/6] download minio server binary ..."
# arm64 for Pi 5
if ! command -v minio >/dev/null 2>&1; then
  curl -fsSLo /usr/local/bin/minio https://dl.min.io/server/minio/release/linux-arm64/minio
  chmod +x /usr/local/bin/minio
fi
if ! command -v mc >/dev/null 2>&1; then
  curl -fsSLo /usr/local/bin/mc https://dl.min.io/client/mc/release/linux-arm64/mc
  chmod +x /usr/local/bin/mc
fi

echo "[3/6] credentials & /etc/default/minio ..."
ACCESS_KEY="passer-velero"
SECRET_KEY="$(openssl rand -base64 36 | tr -dc 'A-Za-z0-9' | head -c 40)"
install -m 0640 -g "$MINIO_USER" /dev/null /etc/default/minio
cat > /etc/default/minio <<EOF
MINIO_ROOT_USER=$ACCESS_KEY
MINIO_ROOT_PASSWORD=$SECRET_KEY
MINIO_VOLUMES="$MINIO_DATA"
MINIO_OPTS="--address $MINIO_LISTEN_ADDR --console-address $MINIO_CONSOLE_ADDR"
EOF
chown root:"$MINIO_USER" /etc/default/minio

echo "[4/6] systemd unit ..."
cat > /etc/systemd/system/minio.service <<'EOF'
[Unit]
Description=MinIO object storage server (Velero backup target for passer)
After=network-online.target zfs-mount.service
Wants=network-online.target zfs-mount.service

[Service]
EnvironmentFile=/etc/default/minio
User=vault
Group=vault
ExecStart=/usr/local/bin/minio server $MINIO_OPTS $MINIO_VOLUMES
Restart=always
RestartSec=5s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now minio.service

echo "[5/6] wait for the health endpoint ..."
for i in {1..30}; do
  if curl -fsS "http://127.0.0.1:9000/minio/health/ready" >/dev/null 2>&1; then
    echo "   up"
    break
  fi
  sleep 2
done

echo "[6/6] create bucket $BUCKET ..."
mc alias set local "http://127.0.0.1:9000" "$ACCESS_KEY" "$SECRET_KEY" >/dev/null
mc mb --ignore-existing "local/$BUCKET" >/dev/null

cat <<EOF

MinIO is up on this Pi at:
  http://192.168.179.2:9000           (S3 API, used by Velero)
  http://192.168.179.2:9001           (web console, personal use)

Bucket: $BUCKET

Credentials — paste these into Flux via SOPS on your laptop:
  access_key = $ACCESS_KEY
  secret_key = $SECRET_KEY

In infrastructure/configs/velero-credentials.secret.yaml the content under
stringData.cloud must be:

[default]
aws_access_key_id=$ACCESS_KEY
aws_secret_access_key=$SECRET_KEY

Then: sops --encrypt --in-place infrastructure/configs/velero-credentials.secret.yaml
and commit.
EOF
