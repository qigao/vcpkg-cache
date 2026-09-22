# vcpkg-cache

Shared third-party C/C++ dependency infrastructure for the qigao repositories.

This repository is the source of truth for two reusable build inputs:

1. **vcpkg overlay ports and binary cache** — custom ports live in `ports/` and compatible binaries are published to the qigao GitHub Packages NuGet feed.
2. **re2c host binaries** — `Qigao.Re2c.Tools` contains prebuilt re2c executables and stdlib data for CI hosts.

Product SDKs such as `Salts.Native` and `SaltsUtils.Native` remain owned and versioned by their product repositories.

## Shared vcpkg baseline

```text
b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01
```

The warm-cache manifest includes the common dependency set used by Salts and SaltsUtils.

## Central overlay ports

`ports/` currently owns:

- `aklomp-base64`
- `c-ares`
- `zstd`

Consumers should not keep private copies of these ports. In GitHub Actions, use:

```yaml
permissions:
  contents: read
  packages: read

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-cache@master
```

The action exports `VCPKG_OVERLAY_PORTS` and configures `VCPKG_BINARY_SOURCES` against:

```text
https://nuget.pkg.github.com/qigao/index.json
```

vcpkg's ABI hash remains the compatibility authority. A cached binary is reused only when the port, triplet, features, toolchain and build configuration are ABI-compatible.

Publishers may opt into write access:

```yaml
permissions:
  contents: read
  packages: write

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-cache@master
    with:
      mode: readwrite
```

## re2c

`Qigao.Re2c.Tools` is a binary/tool package, not a vcpkg library port.

Current package version:

```text
4.6.3
```

It contains host executables for Linux x64, Windows x64, and the macOS runner architecture, plus the re2c stdlib. Android intentionally uses the Linux host binary during cross compilation.

Consumers can restore it with:

```yaml
- uses: qigao/vcpkg-cache/.github/actions/setup-re2c-tools@master
```

## Workflows

- `warm-cache.yml` warms and publishes ABI-compatible vcpkg binary packages for Linux, Windows, macOS and Android.
- `re2c-tools-package.yml` builds and publishes `Qigao.Re2c.Tools`.

Repository-specific `actions/cache` entries may still be used as an optional L1 cache; GitHub Packages is the cross-repository L2/source of truth.
