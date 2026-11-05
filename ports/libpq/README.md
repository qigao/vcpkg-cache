# libpq with externally owned TLS

The overlay uses PostgreSQL 16.9 from vcpkg baseline
`b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01`, with no OpenSSL dependency.
The `ssl` feature is removed, not aliased to another provider. Unix/MinGW
configuration explicitly uses `--without-ssl`; MSVC configuration leaves
its OpenSSL option unset. Default libpq dependencies and its exported CMake
and pkg-config link interfaces must not pull in OpenSSL or BoringSSL.

TLS negotiation, certificate verification and secure transport belong to the
external connection owner. This recipe neither supplies a TLS engine nor
silently replaces one. An application requiring TLS must provide that secure
transport; libpq's upstream sslmode=require/verify-full cannot negotiate TLS
in this build. sslmode=disable on the libpq side is not evidence that the
external transport has authenticated a peer.

## External channel binding

The existing extension remains:

```c
int PQsetExternalChannelBinding(PGconn *conn, const char *type,
                                const void *data, size_t len);
```

Only RFC 5929 tls-server-end-point is accepted. The bytes are copied into
bounded PGconn state before SASL authentication and require sslmode=disable.
They must come from the exact externally verified TLS session. This does not
set ssl_in_use, expose a TLS handle or create a transport loop. Physical
teardown/PQreset clears the binding, so reconnect requires fresh session bytes.
channel_binding=require can select SCRAM-SHA-256-PLUS using that binding.

## Validation

The existing Linux and Windows llvm-mingw source qualification builds the
actual default-feature libpq graph with zstd, rejects OpenSSL/BoringSSL in the
resolved closure and runs the native external-channel-binding behavior test.
No installed CMake consumer project or SSL-provider workflow is retained.
External TLS handshake and full database authentication remain separate
application integration requirements.
