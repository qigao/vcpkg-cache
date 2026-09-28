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

## Central overlay ports

`ports/` currently owns shared vcpkg overlay implementations such as:

- `aklomp-base64`
- `c-ares`
- `libpq`
- `zstd`
- `wabt`

A product may depend on these ports, but the product still owns its manifest and version-selection policy.

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

The action provides the pinned vcpkg executable/scripts environment, overlay ports, and GitHub Packages binary-cache configuration. It does not provide a product manifest and must not build or publish a product SDK.

vcpkg's ABI hash remains the compatibility authority. A cached binary is reused only when the port, triplet, features, toolchain, and build configuration are ABI-compatible.

## Cache contract identity

The shared cache exposes a machine-readable contract identity.

Current semantic contract:

```text
v4
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

## re2c binary

`Qigao.Re2c.Binary` is a host binary/tool package, not a product SDK and not a vcpkg library port.

Current package version:

```text
4.6.3
```

Consumers restore it with:

```yaml
- uses: qigao/vcpkg-cache/.github/actions/setup-re2c-tools@master
```

## Workflows

Allowed workflows in this repository are infrastructure workflows only:

- `warm-cache.yml` — produces the generic cross-platform vcpkg binary cache.
- `validate-cache-contract.yml` — validates the shared vcpkg contract and cross-platform identity.
- vcpkg port-specific validation workflows, where the subject is a central overlay port rather than a product.
- `re2c-tools-package.yml` — builds and publishes `Qigao.Re2c.Binary`.

Product SDK packaging and publishing must live in the product repository.
