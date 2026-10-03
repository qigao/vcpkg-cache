# libpq OpenSSL overlay

This overlay is copied from the vcpkg `libpq` 16.9 port at baseline
`b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01`.

## TLS provider boundary

PostgreSQL 16.9 natively targets the OpenSSL API. This overlay therefore uses
the standard vcpkg `openssl` port (3.5.2 at the pinned baseline) instead of
BoringSSL.

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

- build libpq on supported Windows/Linux triplets;
- verify the installed CMake wrapper resolves `OpenSSL::SSL` for static
  consumers;
- verify a real `sslmode=verify-full` PostgreSQL connection;
- verify the dependency closure contains `openssl` and does not contain
  `boringssl`.
