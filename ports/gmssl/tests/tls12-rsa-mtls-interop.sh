#!/usr/bin/env bash
set -euo pipefail

gmssl_bin="$1"
work="$2"
base_port="${3:-9450}"
rm -rf "$work"
mkdir -p "$work"

openssl req -x509 -newkey rsa:2048 -sha256 -nodes \
  -keyout "$work/ca-key.pem" -out "$work/ca-cert.pem" -days 1 \
  -subj "/CN=GmSSL mTLS Test CA" \
  -addext "basicConstraints=critical,CA:TRUE" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

make_cert() {
  name="$1"
  eku="$2"
  openssl req -new -newkey rsa:2048 -sha256 -nodes \
    -keyout "$work/$name-key.pem" -out "$work/$name.csr" \
    -subj "/CN=$name"
  cat > "$work/$name.ext" <<EOF
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=$eku
subjectAltName=DNS:$name
EOF
  openssl x509 -req -in "$work/$name.csr" \
    -CA "$work/ca-cert.pem" -CAkey "$work/ca-key.pem" -CAcreateserial \
    -out "$work/$name-cert.pem" -days 1 -sha256 -extfile "$work/$name.ext"
}

make_cert localhost serverAuth
make_cert client clientAuth

# GmSSL server verifies an RSA OpenSSL client CertificateVerify.
server_port="$base_port"
"$gmssl_bin" tls12_server \
  -port "$server_port" \
  -cert "$work/localhost-cert.pem" \
  -key "$work/localhost-key.pem" \
  -pass "" \
  -cipher_suite TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 \
  -supported_group prime256v1 \
  -sig_alg rsa_pkcs1_sha256 \
  -renegotiation_info \
  -cert_request \
  -cacert "$work/ca-cert.pem" \
  >"$work/gmssl-server.out" 2>"$work/gmssl-server.err" &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true' EXIT
sleep 1
client_rc=0
echoed=0
printf 'gmssl-mtls-server\n' | openssl s_client \
  -connect "127.0.0.1:$server_port" \
  -servername localhost \
  -CAfile "$work/ca-cert.pem" -verify_hostname localhost \
  -cert "$work/client-cert.pem" -key "$work/client-key.pem" \
  -tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256 \
  -sigalgs rsa_pkcs1_sha256 -quiet \
  >"$work/openssl-client.out" 2>"$work/openssl-client.err" &
client_pid=$!
for _ in $(seq 1 100); do
  if grep -q "gmssl-mtls-server" "$work/openssl-client.out" 2>/dev/null; then
    echoed=1
    break
  fi
  if ! kill -0 "$client_pid" 2>/dev/null; then
    wait "$client_pid" || client_rc=$?
    client_pid=""
    break
  fi
  sleep 0.1
done
if [ -n "$client_pid" ]; then
  kill "$client_pid" 2>/dev/null || true
  wait "$client_pid" 2>/dev/null || true
fi
if [ "$echoed" -ne 1 ]; then
  cat "$work/gmssl-server.err"
  cat "$work/openssl-client.err"
  cat "$work/openssl-client.out"
  echo "OpenSSL mTLS client did not receive the GmSSL echo (rc=$client_rc)" >&2
  exit 1
fi
kill "$server_pid" 2>/dev/null || true
wait "$server_pid" 2>/dev/null || true
trap - EXIT

# GmSSL client signs an RSA CertificateVerify for an OpenSSL server.
openssl_port="$((base_port + 1))"
openssl s_server \
  -accept "$openssl_port" \
  -cert "$work/localhost-cert.pem" -key "$work/localhost-key.pem" \
  -CAfile "$work/ca-cert.pem" -Verify 1 \
  -tls1_2 -cipher ECDHE-RSA-AES128-GCM-SHA256 \
  -sigalgs rsa_pkcs1_sha256 -www -quiet \
  >"$work/openssl-server.out" 2>"$work/openssl-server.err" &
openssl_pid=$!
trap 'kill "$openssl_pid" 2>/dev/null || true' EXIT
sleep 1
"$gmssl_bin" tls12_client \
  -host 127.0.0.1 -port "$openssl_port" \
  -server_name localhost -cacert "$work/ca-cert.pem" \
  -cert "$work/client-cert.pem" -key "$work/client-key.pem" -pass "" \
  -cipher_suite TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 \
  -supported_group prime256v1 -sig_alg rsa_pkcs1_sha256 \
  -get / >"$work/gmssl-client.out" 2>"$work/gmssl-client.err"
grep -q "HTTP/1.0 200" "$work/gmssl-client.out"
kill "$openssl_pid" 2>/dev/null || true
wait "$openssl_pid" 2>/dev/null || true
trap - EXIT

echo "GmSSL TLS 1.2 RSA mTLS interoperability: PASS"
