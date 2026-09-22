# vcpkg-cache

Shared third-party C/C++ dependency infrastructure for the qigao repositories.

This repository is the source of truth for two reusable build inputs:

1. **vcpkg overlay ports and binary cache** — custom ports live in `ports/` and compatible binaries are published to the qigao GitHub Packages NuGet feed.
2. **re2c host binaries** — `Qigao.Re2c.Binary` contains prebuilt re2c executables and stdlib data for CI hosts.

Product SDKs such as `Salts.Native` and `SaltsUtils.Native` remain owned and versioned by their product repositories. `Praktor.Native` is built from Praktor master and published centrally here; its script-enabled SDK profile covers Linux x64, macOS arm64 and Android arm64-v8a. See [Praktor SDK packaging and consumption](packaging/praktor/README.md).

## Shared vcpkg baseline

```text
b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01
```

The root warm-cache manifest includes the common dependency set used across the core native repositories. Repository- or stack-specific ABI combinations live under `manifests/`, including TurboRaft, STUN Linux, and TurboDB PostgreSQL. The TurboDB manifest warms the exact `libpq[zstd]` contract used by the PostgreSQL driver on Linux and Windows.

## Central overlay ports

`ports/` currently owns:

- `aklomp-base64`
- `c-ares`
- `libpq` — PostgreSQL 16.9 client port using BoringSSL
- `zstd`

Consumers should not keep private copies of these ports. In GitHub Actions, use:

```yaml
permissions:
  contents: read
  packages: read

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-cache@master
```

The action owns the canonical vcpkg tool revision, exports `VCPKG_ROOT` and `VCPKG_OVERLAY_PORTS`, and configures a credentialed NuGet source for the qigao GitHub Packages feed. NuGet network operations use a 600-second timeout because large native packages such as Linux `libpq` can exceed NuGet/vcpkg's 100-second default upload timeout. The canonical vcpkg checkout keeps complete git history (with blob filtering) because vcpkg version resolution needs historical port trees. An explicit `token` input may be supplied for cross-repository package access.

vcpkg's ABI hash remains the compatibility authority. A cached binary is reused only when the port, triplet, features, toolchain and build configuration are ABI-compatible.

Downstream repositories are consumers and should use `mode: read`. They may keep a repository-scoped filesystem cache as L1; cache misses may populate that L1, while GitHub Packages remains the shared read-only L2.

Only workflows in this repository publish shared binaries. The central warm workflows use `mode: readwrite` with `packages: write`, keeping package ownership and publication policy in one place. Large stack-specific publishers also verify that their expected package IDs are visible in the GitHub Packages feed after upload; a compile-success/upload-failure must fail the warm workflow rather than silently degrade to a consumer rebuild.

## re2c binary

`Qigao.Re2c.Binary` is a host binary/tool package, not a vcpkg library port.

Current package version:

```text
4.6.3
```

It contains host executables for Linux x64, Windows x64, and the macOS runner architecture, plus the re2c stdlib. Android intentionally uses the Linux host binary during cross compilation.

Consumers restore it with:

```yaml
- uses: qigao/vcpkg-cache/.github/actions/setup-re2c-tools@master
```

Both shared setup actions accept an optional `token` input so consumers can use a package-scoped PAT when repository-scoped `GITHUB_TOKEN` access is insufficient.

## Workflows

- `warm-cache.yml` warms and publishes ABI-compatible vcpkg binary packages for Linux, Windows, macOS and Android, plus stack-specific manifests under `manifests/`.
- `re2c-tools-package.yml` builds and publishes `Qigao.Re2c.Binary`.
- `praktor-sdk-package.yml` builds Praktor master using released dependency SDKs, qualifies relocated script-enabled SDKs across Linux/macOS/Android, and publishes qualified CI versions on master.

Repository-specific `actions/cache` entries may still be used as an optional L1 cache; GitHub Packages is the cross-repository L2/source of truth.


## Stack-specific warm manifests

The root manifest stays focused on broadly shared dependencies. Larger or feature-specific ABI sets are warmed separately:

- `manifests/turboraft-linux` — FlowMQ/TurboRaft Linux-only dependencies such as ZeroMQ.
- `manifests/stun-linux` — STUN/FlexUI/gCanvas Linux graphics and UI dependency union.
- `manifests/turbodb-postgresql` — TurboDB PostgreSQL contract using centralized `libpq[zstd]` with BoringSSL.

This keeps specialized dependency graphs out of unrelated platform jobs while still publishing their binaries into the same GitHub Packages L2 cache.
