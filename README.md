# vcpkg-cache

Shared vcpkg binary-cache infrastructure for the qigao C/C++ repositories.

## Purpose

This repository owns the shared **third-party vcpkg binary cache** used by projects such as
`salts`, `salts-utils`, `chttp`, `praktor`, `turbo-flow`, and `turbodb`.

It does **not** publish Salts or SaltsUtils SDKs. Those remain versioned product packages
(`Salts.Native`, `SaltsUtils.Native`, etc.).

The cache backend is GitHub Packages' NuGet feed:

```text
https://nuget.pkg.github.com/qigao/index.json
```

vcpkg remains responsible for ABI compatibility. Consumers must not invent cache keys based
only on a repository commit or `vcpkg.json`; binary reuse is accepted only when vcpkg's ABI
hash matches the requested port, triplet, features, toolchain, compiler flags, and overlays.

## Baseline

The initial shared baseline is:

```text
b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01
```

This currently matches `qigao/salts` and `qigao/salts-utils`.

## Cache layers

Recommended consumer layout:

```text
L1: local / GitHub Actions filesystem cache
             |
             v miss
L2: qigao GitHub Packages NuGet feed
             |
             v miss
       build from source
```

L1 is optional. GitHub Packages is the cross-repository cache.

## Consumer configuration

Authenticate the qigao GitHub Packages NuGet source and point vcpkg at it.

```bash
VCPKG_BINARY_SOURCES="clear;nuget,https://nuget.pkg.github.com/qigao/index.json,read"
```

Repositories that are explicitly allowed to publish compatible binaries may use `readwrite`
instead of `read`.

GitHub Actions jobs need at least:

```yaml
permissions:
  contents: read
  packages: read
```

A publisher needs `packages: write`.

## Overlay ports

Some repositories currently carry overlay ports. A binary produced from an overlay port is only
reusable when the consumer uses an ABI-compatible copy of that port. The initial warm-cache
workflow therefore warms standard shared dependencies only.

Overlay ports should be centralized here only as a deliberate follow-up migration; copying them
here without changing consumers would not improve cache hits.

## Warm cache

`.github/workflows/warm-cache.yml` builds the shared manifest on the supported CI triplets and
publishes resulting vcpkg binary packages to GitHub Packages.
