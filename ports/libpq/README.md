# libpq GmSSL TLS overlay

This overlay is copied from the vcpkg `libpq` 16.9 port at baseline
`b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01`.

The overlay uses the GmSSL OpenSSL Compatibility Layer as its only TLS provider.
PostgreSQL continues to build its OpenSSL-shaped TLS implementation, but the
installed `ssl`/`crypto` headers and libraries are backed by GmSSL. The
provider boundary remains centralized in `tls-provider.cmake`; there is no
BoringSSL fallback or dual-provider mode.

When updating the vcpkg baseline, refresh this directory from the matching
upstream `ports/libpq` directory, reapply the dependency change, and verify a
real `sslmode=verify-full` connection in addition to the normal build tests.

## Provider boundary

Provider-specific configure identity, compatibility version, and Windows patch
selection live in `tls-provider.cmake`. This slice deliberately keeps BoringSSL
active and changes no libpq TLS behavior; it only removes provider details from
the generic port logic so the next migration can replace the provider without
adding fallback or dual-provider paths.

The canonical GmSSL port is owned independently by `ports/gmssl` on master.

## Migration gate

A successful build alone is not sufficient. The provider switch must pass a real
PostgreSQL TLS connection with `sslmode=verify-full` before #86 can close.
