# vcpkg-cache

Shared third-party C/C++ dependency infrastructure for the qigao repositories.

This repository is the source of truth for two reusable build inputs:

1. **vcpkg overlay ports and binary cache** — custom ports live in `ports/` and compatible binaries are published to the qigao GitHub Packages NuGet feed.
2. **re2c host binaries** — `Qigao.Re2c.Binary` contains prebuilt re2c executables and stdlib data for CI hosts.

Product SDKs such as `Salts.Native` and `SaltsUtils.Native` remain owned and versioned by their product repositories. `Praktor.Native` and `FlowMQ.Native` are built from their product default branches and published centrally here; Praktor supports Linux x64, macOS arm64 and Android arm64-v8a Release with TurboScript enabled, while FlowMQ's initial profile is Linux x64 Release. See [Praktor SDK packaging and consumption](packaging/praktor/README.md) and [FlowMQ SDK packaging and consumption](packaging/flowmq/README.md).

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

The action does not download or bootstrap a vcpkg executable. It takes only the executable from the runner/toolchain (preferring `VCPKG_ROOT`, then `VCPKG_INSTALLATION_ROOT`, then `vcpkg` on `PATH`), requires it to match `vcpkg-tool-version.txt`, and combines it with a checkout of the exact canonical vcpkg scripts revision declared by the central `builtin-baseline`. This prevents hosted-runner image rollouts from changing the scripts/ports root and therefore changing binary-cache ABI keys between otherwise identical jobs. If no usable runner executable is present, setup fails immediately; there is no `bootstrap-vcpkg` or release-asset curl fallback. NuGet network operations use a 600-second timeout because large native packages such as Linux `libpq` can exceed NuGet/vcpkg's 100-second default upload timeout. An explicit `token` input may be supplied for cross-repository package access.

vcpkg's ABI hash remains the compatibility authority. A cached binary is reused only when the port, triplet, features, toolchain and build configuration are ABI-compatible.

Downstream repositories are consumers and should use `mode: read`. The runner supplies execution only; `vcpkg-tool-version.txt` fixes the executable identity and the central baseline fixes the vcpkg scripts/registry identity. Product SDKs and host tools such as re2c are restored directly from NuGet packages; C/C++ third-party dependencies remain owned by `vcpkg install`, with GitHub Packages/NuGet acting only as the shared vcpkg binary-cache backend. Consumers may keep a repository-scoped filesystem cache as L1; strict release/ABI gates should use `--only-binarycaching` so a shared-cache miss is RED instead of silently rebuilding.

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
- `praktor-sdk-package.yml` builds Praktor master using released dependency SDKs, tests a restored `Praktor.Native` package, and publishes qualified CI versions on master.
- `flowmq-sdk-package.yml` pins one FlowMQ main commit, builds Linux/Windows/macOS/Android SDK profiles using released Salts/SaltsUtils packages and cache-only vcpkg restores, packs one multi-platform `FlowMQ.Native`, qualifies clean-restored external consumers on every RID, and publishes only after all gates pass.

Repository-specific `actions/cache` entries may still be used as an optional L1 cache; GitHub Packages is the cross-repository L2/source of truth.


## Stack-specific warm manifests

The root manifest stays focused on broadly shared dependencies. Larger or feature-specific ABI sets are warmed separately:

- `manifests/flowmq` — exact BoringSSL + ZeroMQ dependency set for FlowMQ SDK packaging on Linux, Windows, macOS, and Android arm64.
- `manifests/turboraft-linux` — TurboRaft Linux-only dependency warm-up.
- `manifests/stun-linux` — STUN/FlexUI/gCanvas Linux graphics and UI dependency union.
- `manifests/turbodb-postgresql` — TurboDB PostgreSQL contract using centralized `libpq[zstd]` with BoringSSL.

This keeps specialized dependency graphs out of unrelated platform jobs while still publishing their binaries into the same GitHub Packages L2 cache.
