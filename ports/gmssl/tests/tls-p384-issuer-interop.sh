#!/usr/bin/env bash
# Test-only OpenSSL oracle and peer: P-384 issuing CA signs a P-256 TLS leaf
# with ECDSA/SHA-384. Production TLS must remain GmSSL-only.
set -euo pipefail

gmssl_bin="${1:?installed gmssl executable required}"
work="${2:?temporary work directory required}"
base_port="${3:-9460}"

test -x "$gmssl_bin"
rm -rf "$work"
mkdir -p "$work"

# Create a fresh CA and leaf on the runner to exercise genuine DER certificate
# signatures, not merely a fixed OID vector.
openssl ecparam -name secp384r1 -genkey -noout -out "$work/ca.key"
openssl req -new -x509 -key "$work/ca.key" -sha384 -days 2 \
  -subj "/CN=GmSSL P384 Test CA" -out "$work/ca.pem" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
openssl ecparam -name prime256v1 -genkey -noout -out "$work/server.key"
openssl req -new -key "$work/server.key" \
  -subj "/CN=localhost" -out "$work/server.csr"
cat > "$work/server.ext" <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=serverAuth
subjectAltName=DNS:localhost
EOF
openssl x509 -req -in "$work/server.csr" \
  -CA "$work/ca.pem" -CAkey "$work/ca.key" -CAcreateserial \
  -sha384 -days 2 -extfile "$work/server.ext" \
  -out "$work/server.pem"

# Independent OpenSSL oracle: the fixture really has the requested curve,
# signature OID, CA semantics, EKU and hostname identity.
openssl verify -CAfile "$work/ca.pem" -purpose sslserver \
  -verify_hostname localhost "$work/server.pem"
openssl x509 -in "$work/server.pem" -noout -text \
  | grep -qi 'Signature Algorithm: ecdsa-with-SHA384'
openssl x509 -in "$work/server.pem" -noout -pubkey \
  | openssl pkey -pubin -noout -text | grep -q 'prime256v1'
openssl x509 -in "$work/ca.pem" -noout -pubkey \
  | openssl pkey -pubin -noout -text | grep -q 'secp384r1'

# A second independently generated CA must never authenticate this leaf.
openssl ecparam -name secp384r1 -genkey -noout -out "$work/wrong-ca.key"
openssl req -new -x509 -key "$work/wrong-ca.key" -sha384 -days 2 \
  -subj "/CN=GmSSL Wrong CA" -out "$work/wrong-ca.pem" \
  -addext "basicConstraints=critical,CA:TRUE,pathlen:1" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"
if openssl verify -CAfile "$work/wrong-ca.pem" -purpose sslserver \
   -verify_hostname localhost "$work/server.pem" >"$work/negative-ca.out" 2>&1; then
  echo "Independent OpenSSL oracle unexpectedly trusted a wrong CA" >&2
  exit 1
fi

server_pid=""
cleanup() {
  if [ -n "$server_pid" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
    server_pid=""
  fi
}
trap cleanup EXIT

run_version() {
  local version="$1"
  local port="$2"
  local openssl_version cipher suite
  case "$version" in
    12)
      openssl_version="-tls1_2"
      cipher="ECDHE-ECDSA-AES128-GCM-SHA256"
      suite="TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"
      ;;
    13)
      openssl_version="-tls1_3"
      cipher="TLS_AES_128_GCM_SHA256"
      suite="TLS_AES_128_GCM_SHA256"
      ;;
    *) return 2 ;;
  esac

  local -a server_args=(
    -accept "127.0.0.1:$port"
    -cert "$work/server.pem" -key "$work/server.key"
    -cert_chain "$work/ca.pem"
    "$openssl_version"
    -sigalgs ecdsa_secp256r1_sha256
    -www
  )
  if [ "$version" = 12 ]; then
    server_args+=( -cipher "$cipher" )
  else
    server_args+=( -ciphersuites "$cipher" )
  fi

  openssl s_server "${server_args[@]}" \
    >"$work/server-$version.out" 2>"$work/server-$version.err" &
  server_pid=$!
  sleep 1
  if ! kill -0 "$server_pid" 2>/dev/null; then
    cat "$work/server-$version.err" >&2
    echo "OpenSSL TLS $version test peer terminated" >&2
    return 1
  fi

  local -a client_args=(
    -host 127.0.0.1 -port "$port"
    -server_name localhost -cacert "$work/ca.pem"
    -cipher_suite "$suite"
    -supported_group prime256v1
    -sig_alg ecdsa_secp256r1_sha256
    -get / -verbose
  )
  if ! "$gmssl_bin" "tls${version}_client" "${client_args[@]}" \
      >"$work/client-$version.out" 2>"$work/client-$version.err"; then
    cat "$work/server-$version.err" >&2
    cat "$work/client-$version.err" >&2
    echo "GmSSL TLS $version rejected valid P384 CA / P256 leaf SHA384" >&2
    return 1
  fi
  if ! grep -Eq 'HTTP/1[.]0 200' "$work/client-$version.out"; then
    cat "$work/client-$version.out" >&2
    cat "$work/client-$version.err" >&2
    echo "TLS $version handshake did not reach authenticated HTTP" >&2
    return 1
  fi

  # Preserve strict GmSSL CA and identity checks on the same server.
  # The pinned gmssl CLI exits 0 even after a failed handshake. Require
  # an explicit handshake rejection diagnostic and absence of HTTP, not rc != 0.
  "$gmssl_bin" "tls${version}_client" \
      -host 127.0.0.1 -port "$port" -server_name localhost \
      -cacert "$work/wrong-ca.pem" -cipher_suite "$suite" \
      -supported_group prime256v1 -sig_alg ecdsa_secp256r1_sha256 \
      -get / >"$work/wrong-ca-$version.out" 2>"$work/wrong-ca-$version.err" || true
  if grep -Eq 'HTTP/1[.]0 200' "$work/wrong-ca-$version.out" \
      || ! grep -q 'client: error' "$work/wrong-ca-$version.err"; then
    cat "$work/wrong-ca-$version.err" >&2
    echo "GmSSL TLS $version failed to reject untrusted CA at handshake" >&2
    return 1
  fi
  "$gmssl_bin" "tls${version}_client" \
      -host 127.0.0.1 -port "$port" -server_name wrong.example \
      -cacert "$work/ca.pem" -cipher_suite "$suite" \
      -supported_group prime256v1 -sig_alg ecdsa_secp256r1_sha256 \
      -get / >"$work/wrong-host-$version.out" 2>"$work/wrong-host-$version.err" || true
  if grep -Eq 'HTTP/1[.]0 200' "$work/wrong-host-$version.out" \
      || ! grep -q 'client: error' "$work/wrong-host-$version.err"; then
    cat "$work/wrong-host-$version.err" >&2
    echo "GmSSL TLS $version failed to reject wrong hostname at handshake" >&2
    return 1
  fi

  cleanup
  echo "GmSSL TLS $version P-384 CA / P-256 leaf SHA384: PASS"
}

run_version 12 "$base_port"
run_version 13 "$((base_port + 1))"
