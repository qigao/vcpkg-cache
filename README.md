# vcpkg-cache

Shared native dependency infrastructure for the qigao C/C++ repositories.

This repository is the **single source of truth** for:

- shared vcpkg overlay ports;
- vcpkg binary packages published to GitHub Packages;
- shared host build tools such as re2c.

Product SDKs such as `Salts.Native` and `SaltsUtils.Native` remain owned and versioned by
their product repositories.

## vcpkg baseline

The shared baseline is:

```text
b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01
```

Consumers should use the same baseline when they expect binary-cache hits.

## Central overlay ports

The authoritative overlays live under `ports/`.

Current centralized ports:

- `aklomp-base64`
- `c-ares`
- `zstd`

Do not copy these ports into consumer repositories. Changes to their build contract must be made
here first and then warmed into GitHub Packages.

## Shared binary cache

`.github/workflows/warm-cache.yml` warms the manifest for the supported CI targets:

- Linux x64
- Windows x64
- native macOS
- Android arm64

vcpkg itself decides whether a cached binary is compatible by its ABI hash. The cache must not
be keyed only by a repository SHA or by `vcpkg.json`.

### GitHub Actions consumer

A consumer can configure both the centralized overlays and the GitHub Packages binary source
with:

```yaml
permissions:
  contents: read
  packages: read

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-cache@master
    with:
      mode: read
```

The action exports `VCPKG_OVERLAY_PORTS`, `VCPKG_BINARY_SOURCES`, and
`VCPKG_NUGET_REPOSITORY`.

Normal consumers should use `mode: read`. The central warm-cache workflow is the normal writer.

## re2c host tools

re2c is centralized here because it is a host code generator rather than a Salts product
dependency. Android cross-builds still consume a Linux/macOS/Windows host re2c executable.

The package owned by this repository is:

```text
Qigao.VcpkgCache.Re2c.Tools 4.6.3
```

Consumers can restore it with:

```yaml
permissions:
  contents: read
  packages: read

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-re2c-tools@master
```

The action exports `RE2C_ROOT` and adds the matching host executable to `PATH`.

## Ownership rules

1. Third-party overlay ports belong here, not in `salts`, `salts-utils`, or downstream repos.
2. Shared third-party binaries are published by the warm-cache workflow.
3. Host build tools that are reused across repositories belong here.
4. Product libraries and their SDK packages remain in their product repositories.
5. Consumers use `master` for this infrastructure repository and let vcpkg's ABI hash decide
   whether a binary can be reused.
