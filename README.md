# vcpkg-cache

Shared **vcpkg infrastructure** and **re2c host tooling** for the qigao repositories.

This repository owns exactly two reusable build inputs:

1. **vcpkg infrastructure** — pinned vcpkg tool/scripts identity, shared overlay ports/versions, setup action, and ABI-compatible binary-cache production.
2. **re2c host binaries** — `Qigao.Re2c.Binary` plus the reusable setup action.

## Ownership boundary

This repository does **not** own product dependency graphs or product releases.

Product repositories must own:

- their own `vcpkg.json` / `vcpkg-configuration.json`;
- product- or stack-specific dependency selection and qualification;
- native SDK build/test/package workflows;
- product NuGet packages and publication.

Accordingly, this repository must not contain a product `manifests/` tree, product SDK packaging directories, or product release workflows. Consumers use the shared setup action and binary cache, but keep dependency policy in their own repository.

## Shared vcpkg baseline

The generic warm-cache manifest at the repository root uses:

```text
b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01
```

The root `vcpkg.json` is only a generic cache warm set. It is **not** a dependency contract for Salts, SaltsUtils, FlowMQ, TurboDB, TurboRaft, TurboWasm, STUN, Praktor, or any other product.

The setup action bootstraps the official vcpkg executable from the checkout selected by
`vcpkg-scripts-revision.txt`, then checks it against `vcpkg-tool-version.txt`.
It does not use the runner image's preinstalled executable. When updating the shared
tool identity, keep these two files aligned with the checkout's bootstrap metadata.
Bootstrap or identity failures stop setup before dependency restoration.

## Central overlay ports

`ports/` currently owns shared vcpkg overlay implementations such as:

- `aklomp-base64`
- `c-ares`
- `libpq`
- `zstd`
- `wabt`
- [`wtl`](ports/wtl/vcpkg.json) — full upstream WTL 10.0.10320 headers/Samples/AppWizard, immutable GitHub release SHA512; no dependency on Microsoft's `atl` vcpkg detection port. Applications link their own `OpenATL::ATL` source-tree target. This header-only port does **not** install an OpenATL SDK.
- [`tre`](ports/tre/README.md) (static regex and approximate matching)
- `mir-jit` (static MIR core/generator; Linux, macOS, Android and Windows x64)

A product may depend on these ports, but the product still owns its manifest and version-selection policy.

The MIR port keeps its pinned upstream source and executable-memory budget
patch on Windows x64. Windows cache jobs warm both the root manifest and the
unversioned MIR dependency graph used by optional-feature consumers such as
TurboWasm, then verify read-only NuGet restoration. Windows x86 and ARM64
remain unsupported. Product JIT/runtime tests belong to the consuming product.

Consumers configure vcpkg with:

```yaml
permissions:
  contents: read
  packages: read

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-cache@master
    with:
      mode: read
```

The action provides the pinned vcpkg executable/scripts environment, overlay ports, and GitHub Packages binary-cache configuration. The Microsoft vcpkg repository is materialized at the exact pinned scripts SHA with its complete reachable Git objects: the checkout is non-shallow and has no promisor remote or partial-clone filter. This is required because vcpkg versioning resolves historical port snapshots by `git-tree` SHA; consumers must never need repository-local `git fetch --unshallow` workarounds. The action does not provide a product manifest and must not build or publish a product SDK.

vcpkg's ABI hash remains the compatibility authority. A cached binary is reused only when the port, triplet, features, toolchain, and build configuration are ABI-compatible.

The generic `cache-contracts/header-only/vcpkg.json` profile keeps an isolated
simde dependency graph. The arm64 warm producer installs it before the full SDK
dependency set, and a fresh runner verifies read-only NuGet restoration with an
empty L1 cache and `--only-binarycaching`. This profile covers the header-only ABI
whose tool record is `cmake 0`; warming a larger CMake-dependent graph produces a
different ABI even when the simde source, features and triplet match. Both graphs
use the pinned shared tools and their actual ABI hashes. Consumer cache misses
remain explicit failures.

## Cache contract identity

The shared cache exposes a machine-readable contract identity.

Current semantic contract:

```text
v6
```

`setup-vcpkg-cache` exports:

- `VCPKG_CACHE_CONTRACT_VERSION` / `contract_version`
- `VCPKG_CACHE_REVISION` / `cache_revision`
- `VCPKG_TOOL_REVISION` / `tool_revision`
- `VCPKG_SCRIPTS_REVISION` / `scripts_revision`

The cache revision is derived only from shared vcpkg infrastructure: overlay ports, versions, setup/toolchain logic, the generic root warm manifest, and pinned vcpkg identities. Product manifests are intentionally outside this hash and belong to the consuming repository.

Consumer L1 caches should include both the central cache revision and their own manifest hash:

```yaml
- id: shared-vcpkg
  uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-cache@master
  with:
    mode: read

- uses: actions/cache@v4
  with:
    path: build/vcpkg-binary-cache
    key: >-
      vcpkg-l1-v4-${{ runner.os }}-${{ runner.arch }}-
      ${{ steps.shared-vcpkg.outputs.contract_version }}-
      ${{ steps.shared-vcpkg.outputs.cache_revision }}-
      ${{ hashFiles('vcpkg.json', 'vcpkg-configuration.json') }}
```

## Product-owned cache production

Product-specific dependency closures and binary-cache producers belong in the product repository. For example, TurboMedia owns its media overlays and media binary-cache production rather than delegating those packages back to this infrastructure repository.

`vcpkg-cache` provides the canonical vcpkg tool/scripts identity, shared infrastructure overlays, and GitHub Packages transport. It must not reconstruct or warm a product dependency graph from another repository.

## re2c binary

`Qigao.Re2c.Binary` is a host binary/tool package, not a product SDK and not a vcpkg library port.

The curl reader's default published package lock is:

```text
version: 4.6.4
sha256: 9e1eb668eb818e81c6ba50d9342f874247b2ea66f33a00d2e253053ef1474269
```

Consumers restore it with:

```yaml
- uses: qigao/vcpkg-cache/.github/actions/setup-re2c-tools@PINNED_COMMIT
  with:
    version: "4.6.4"
    sha256: "9e1eb668eb818e81c6ba50d9342f874247b2ea66f33a00d2e253053ef1474269"
```

Omitting both inputs selects the same explicit published lock. Overrides must
supply both `version` and `sha256`; a single override fails before download.
The reader does not select the latest version, accept a version wildcard, or
fall back after a failed restore. It verifies the whole nupkg digest, unique
package identity, safe member paths, native binary and nonempty C syntax /
Unicode data before extracting or executing payloads. Only a successful
`--version` run publishes `RE2C_ROOT`, `RE2C_PACKAGE_VERSION`,
`RE2C_PACKAGE_SHA256` and the binary search path. Use a fresh destination.

The published 4.6.4 package contains Linux x64/ARM64, macOS ARM64 and Windows
x64 payloads; it contains no macOS x64 payload. The existing 4.6.4 Linux x64
binary requires `GLIBCXX_3.4.32`, so pinning its identity does not make it
compatible with Ubuntu 22.04. A rebuilt package must be separately qualified
and published before its real version and digest replace this lock.

The direct CLI requires both arguments, with no implicit version selection:

```sh
python scripts/github-packages.py re2c "$RUNNER_TEMP/qigao-re2c-binary" \
  --version 4.6.4 \
  --sha256 9e1eb668eb818e81c6ba50d9342f874247b2ea66f33a00d2e253053ef1474269
```

## Workflows

Allowed workflows in this repository are infrastructure workflows only:

- `warm-cache.yml` — produces the generic cross-platform vcpkg binary cache.
- `validate-cache-contract.yml` — validates the shared vcpkg contract and cross-platform identity.
- vcpkg port-specific validation workflows, where the subject is a central overlay port rather than a product.
- `re2c-tools-package.yml` — builds and publishes `Qigao.Re2c.Binary`.

Product SDK packaging and publishing must live in the product repository.
