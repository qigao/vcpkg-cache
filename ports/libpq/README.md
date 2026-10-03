# libpq TLS/no-TLS overlay

This overlay is copied from the vcpkg `libpq` 16.9 port at baseline
`b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01`.

## TLS provider boundary

PostgreSQL 16.9 natively targets the OpenSSL API when TLS is enabled. This
overlay exposes that support as the explicit `ssl` vcpkg feature. The feature
uses the standard vcpkg `openssl` port (3.5.2 at the pinned baseline) instead
of BoringSSL.

A build with `default-features=false` and without `ssl` is a true no-SSL
profile: it does not configure PostgreSQL TLS and its dependency closure must
contain neither OpenSSL nor BoringSSL.

Provider-specific build settings live in `tls-provider.cmake`; the rest of
the port consumes that contract. There is no runtime TLS-provider selection and
no BoringSSL fallback.

The Windows build links vcpkg OpenSSL's `libssl` / `libcrypto` libraries.
The BoringSSL-only protocol/error/BIO compatibility patches are intentionally
not applied.

This choice is separate from Salts/CNet's TLS migration: CNet can use native
GmSSL because it owns a provider-neutral feed/drain engine boundary, while
libpq keeps its upstream OpenSSL contract rather than carrying a private
PostgreSQL/GmSSL TLS fork.

## Validation gate

When changing this overlay:

- build both `libpq[ssl]` and no-SSL profiles on supported Windows/Linux triplets;
- verify TLS-enabled installed CMake wrappers resolve `OpenSSL::SSL` for static consumers;
- verify a real `sslmode=verify-full` PostgreSQL connection for `libpq[ssl]`;
- verify the TLS-enabled closure contains `openssl` and no `boringssl`;
- verify the no-SSL closure contains neither `openssl` nor `boringssl`, and
  installed pkg-config/CMake consumers link without an OpenSSL dependency.

The no-SSL profile is appropriate only when the database connection is
intentionally plaintext or protected by a separately designed secure transport.
It does not silently replace libpq TLS with CNet/GmSSL.
