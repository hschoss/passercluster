#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
secrets_dir="${repo_root}/secrets"
crt_file="${secrets_dir}/passer-lan.crt"
key_file="${secrets_dir}/passer-lan.key"
days="${PASSER_LAN_CERT_DAYS:-3650}"

if ! command -v openssl >/dev/null 2>&1; then
  echo "ERROR - openssl is not installed" >&2
  exit 1
fi

mkdir -p "$secrets_dir"
umask 077

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

cat >"$tmpdir/openssl.cnf" <<'EOF'
[req]
default_bits = 4096
prompt = no
default_md = sha256
distinguished_name = req_distinguished_name
x509_extensions = v3_req

[req_distinguished_name]
CN = passer.lan

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = passer.lan
DNS.2 = *.passer.lan
EOF

openssl req -x509 -nodes -newkey rsa:4096 -days "$days" -keyout "$key_file" -out "$crt_file" -config "$tmpdir/openssl.cnf" -extensions v3_req

chmod 600 "$key_file"

echo "Wrote ${crt_file}"
echo "Wrote ${key_file}"
