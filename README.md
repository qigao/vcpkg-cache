# vcpkg-cache

Shared **vcpkg infrastructure**, **re2c/Lemon host tooling**, and
**pinned compiler setup actions** for the qigao repositories.

This repository owns three reusable infrastructure inputs:

1. **vcpkg infrastructure** — pinned vcpkg tool/scripts identity, shared overlay ports/versions, setup action, and ABI-compatible binary-cache production.
2. **Host generators** — `Qigao.Re2c.Binary` plus its setup action, and paired `Qigao.Lemon.Binary` executable/template tools for CMake.
3. **Compiler selection** — Windows uses pinned llvm-mingw/UCRT, Linux/macOS use the runner's native Clang, and obfuscator-llvm has no global LLVM-version restriction. GCC is test-only. There are no Clang verification CI jobs, probes, or synthetic consumer projects. See [compiler setup](docs/setup-compiler-actions.md) and [Release policy](docs/release-obfuscation-toolchains.md).

The curl-only vcpkg setup action provides a [pinned native Windows pkg-config](docs/curl-only-github-packages.md#windows-pkg-config), avoiding vcpkg's MSYS2 download for pkg-config alone. CI must not install or execute Mono; external native packages and tool archives are downloaded with curl. The legacy Mono/NuGet setup action has been removed. Existing action tags and SHA pins remain immutable.

For product-selected native SDK packages and public tool archives, the
[shared restore CLI and Action](docs/restore-native-dependency.md) provide
SHA-256 locked downloads, safe extraction, explicit payload selection and
consistent local/CI paths. Products retain their dependency locks and SDK
validation. An explicit latest-package resolver writes an exact version/hash
lock; the Action and CMake module both restore that lock. These entry points are
available in the `v0.1.002` infrastructure release.

The [paired Lemon executable/template package](packaging/lemon/README.md)
`Qigao.Lemon.Binary` 1.0.0 and `Lemon::Lemon` CMake helper are available with
`v0.1.003`. Earlier infrastructure tags remain unchanged.

Obfuscation is selected **once at compiler setup**, with
`obfuscator: "true"` in `setup-llvm-native` or `setup-llvm-mingw`.
The action prepares the single upstream eshard/obfuscator-llvm pass and
activates it for product C/C++ source compilation through the product-side
toolchain compiler launcher. No `SENSITIVE_TARGETS`, `ORDINARY_TARGETS`,
target lists or product-level per-target flags are required. Existing
third-party vcpkg binary packages retain their independent ABI and are
not retroactively obfuscated. See [compiler setup](docs/setup-compiler-actions.md).

## Ownership boundary

This repository does **not** own product dependency graphs or product releases.

Product repositories must own:

- their own `vcpkg.json` / `vcpkg-configuration.json`;
- product- or stack-specific dependency selection and qualification;
- native SDK build/test/package workflows;
- product NuGet packages and publication.

Accordingly, this repository must not contain a product `manifests/` tree, product SDK packaging directories, or product release workflows. Consumers use the shared setup action and binary cache, but keep dependency policy in their own repository.

## Versioned infrastructure releases

The current shared **Action / registry source** release is
[`v0.1.7`](https://github.com/qigao/vcpkg-cache/releases/tag/v0.1.7).
Downstream workflows use a published version, not `@master`, for this cache
repository's reusable Actions. `v0.1.7` registers GmSSL 3.2.0#44, including
bounded TLS 1.3 client/server session support, certificate signature/depth/anchor
constraints, credential imports and PRF failure erasure. It retains miniaudio
0.11.22#1 and the existing native compiler, ccache, curl-only transport,
package/tool CLI, CMake entry points and Lemon tools.
The `v0.1.0`, `v0.1.002` and `v0.1.003` tags stay immutable. Candidate PR validation can select an exact commit
before a version is released.
The Git registry's `reference` uses the selected release tag. Its `baseline` is a
required exception: vcpkg requires the **40-hex Git commit** resolved from
that same release tag. This is a registry schema constraint, not a different
infrastructure version; do not put a tag or a placeholder in `baseline`.

The release tag versions infrastructure source and Action code; it is not a
binary cache ABI and does not imply every platform's immutable NuGet ZIP is
published. Native packages continue to be identified only by complete
vcpkg ABI hashes and accepted through the existing strict cache gates.
See [release v0.1.7](https://github.com/qigao/vcpkg-cache/releases/tag/v0.1.7) and the historical
[release v0.1.0](https://github.com/qigao/vcpkg-cache/releases/tag/v0.1.0).

## Shared vcpkg baseline

The reference dependency manifest at the repository root uses:

```text
b1b19307e2d2ec1eefbdb7ea069de7d4bcd31f01
```

The root `vcpkg.json` is a reference dependency set for infrastructure and manual shared-cache production. It is **not** a dependency contract for Salts, SaltsUtils, FlowMQ, TurboDB, TurboRaft, TurboWasm, STUN, Praktor, or any other product. Products own dependency installation through their normal builds; there is no cache prewarming prerequisite or automatic warm workflow.

The setup action bootstraps the official vcpkg executable selected by
`vcpkg-scripts-revision.txt`, then checks it against `vcpkg-tool-version.txt`.
Windows downloads the matching x64 or ARM64 release through the shared curl
downloader with pinned SHA256 checks; Unix uses the pinned curl bootstrap.
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
- [`tre`](ports/tre/README.md) (retired for new work; historical compatibility overlay only)
- `ugrep` 7.8.5 (CLI tools, PCRE2 enabled; native Linux/macOS and Windows MSVC x86/x64)
- `bfs` 4.1.5 (POSIX find CLI; native Linux/macOS)
- `mir-jit` (static MIR core/generator; Linux, macOS, Android and Windows x64)

A product may depend on these ports, but the product still owns its manifest and version-selection policy.

The reference manifest includes builtin `pcre2` (10.46 at the pinned baseline,
including its platform-default JIT feature). The search-tool overlays pin source
archives with SHA512 checksums and install executables under `tools/<port>`;
they do not export application libraries. `ugrep` requires PCRE2 for `-P` and
omits optional compression libraries. `bfs` disables optional third-party
integrations to keep the cached feature set independent of host packages.
Cross builds skip both tools. Build-time consumers declare tools with
`"host": true`; neither tool replaces a product's filesystem/index lifecycle.
TRE is retired in favor of PCRE2 and is no longer in the reference manifest.
New regex dependencies must use `pcre2`. The proposed TRE API extension,
frozen-contract qualification and publisher work in #248/#249/#251/#252 are
cancelled and closed, not accepted as completed publication. The existing
overlay remains only for historical consumers during migration; immutable
release tags and old packages are not rewritten. Removing a consumer's TRE
dependency requires a real PCRE2 API/semantic migration in that consumer.

Manifest or port changes do not trigger cache prewarming. The manually dispatched
[shared cache producer](docs/vcpkg-cache-production.md) builds the root reference
manifest and can publish immutable ABI packages through the shared curl transport.
The existing versioned `v0.1.0` source release does not acquire new overlays
retroactively.

The MIR port keeps its pinned upstream source and executable-memory budget
patch on Windows x64. Windows x86 and ARM64 remain unsupported. Product
JIT/runtime tests belong to the consuming product.

Consumers configure vcpkg with `v0.1.5` and select the product's actual manifest
and triplets:

```yaml
permissions:
  contents: read
  packages: read

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-curl-cache@v0.1.5
    with:
      mode: read
      restore-packages: "false"
      manifest-root: .
      triplet: x64-linux
      host-triplet: x64-linux
```

The action provides the pinned vcpkg executable/scripts environment, overlay ports, and exact GitHub Packages downloads over authenticated curl. vcpkg receives only the local files binary-cache provider; no NuGet executable, .NET restore or Mono is invoked. The Microsoft vcpkg repository is materialized at the exact pinned scripts SHA with its complete reachable Git objects: the checkout is non-shallow and has no promisor remote or partial-clone filter. This is required because vcpkg versioning resolves historical port snapshots by `git-tree` SHA; consumers must never need repository-local `git fetch --unshallow` workarounds. The action does not provide a product manifest and must not build or publish a product SDK.


For normal product builds, `restore-packages: "false"` prepares the canonical
tools and local files cache, validates the real manifest/triplets/features, and
leaves dependency installation to the product's existing CMake/vcpkg build.
Source archives and native tools are downloaded through curl/libcurl with their
pinned hashes. This mode does not contact the remote binary feed and does not
catch or ignore a failed restore. It does not configure the product's CMake
features; the product retains that responsibility.

The default `restore-packages: "true"` requires every exact remote ABI archive
and keeps the strict cache-qualification behavior, including failure on missing,
inaccessible or corrupt packages. Use it when binary restoration is an explicit
requirement. A normal product build must not require a separate cache producer
or permission change before it can compile its declared dependencies.

vcpkg's ABI hash remains the compatibility authority. A cached binary is reused only when the port, triplet, features, toolchain, and build configuration are ABI-compatible.

## Cache contract identity

The shared cache exposes a machine-readable contract identity.

Current semantic contract:

```text
v8
```

`setup-vcpkg-curl-cache` exports:

- `VCPKG_CACHE_CONTRACT_VERSION` / `contract_version`
- `VCPKG_CACHE_REVISION` / `cache_revision`
- `VCPKG_TOOL_REVISION` / `tool_revision`
- `VCPKG_SCRIPTS_REVISION` / `scripts_revision`

The cache revision is derived only from shared vcpkg infrastructure: overlay ports, versions, setup/toolchain logic, the generic root warm manifest, and pinned vcpkg identities. Product manifests are intentionally outside this hash and belong to the consuming repository.

Consumer L1 caches should include both the central cache revision and their own manifest hash:

```yaml
- id: shared-vcpkg
  uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-curl-cache@v0.1.5
  with:
    mode: read
    restore-packages: "false"
    manifest-root: .
    triplet: x64-linux
    host-triplet: x64-linux

- uses: actions/cache@v4
  with:
    path: build/vcpkg-binary-cache
    key: >-
      vcpkg-l1-v4-${{ runner.os }}-${{ runner.arch }}-
      ${{ steps.shared-vcpkg.outputs.contract_version }}-
      ${{ steps.shared-vcpkg.outputs.cache_revision }}-
      ${{ hashFiles('vcpkg.json', 'vcpkg-configuration.json') }}
```

## Shared and product-owned cache production

`curl-only-vcpkg-producer.yml` builds the root reference manifest for a selected
native Linux, macOS or Windows x64/ARM64 platform. Its default dispatch saves
ABI ZIPs as a workflow artifact; `publish: true` also uploads them to GitHub
Packages through the existing `native-cache-publish` environment. It runs no
tests. See [dispatch and setup instructions](docs/vcpkg-cache-production.md).

Downstream apps can restore these packages when their resolved ABI matches,
including port versions, features, triplets, compiler and dependency ABIs.
A package from a different dependency graph is reusable only if its ABI matches.

Product-specific dependency closures and binary-cache producers belong in the product repository. For example, TurboMedia owns its media overlays and media binary-cache production rather than delegating those packages back to this infrastructure repository.

`vcpkg-cache` provides the canonical vcpkg tool/scripts identity, shared infrastructure overlays, and GitHub Packages transport. It must not reconstruct or warm a product dependency graph from another repository.

## re2c binary

`Qigao.Re2c.Binary` is a host binary/tool package, not a product SDK and not a vcpkg library port.

The curl reader's default published package lock is:

```text
version: 4.6.7
sha256: fe3c64ef3c25a28a9e5143bf2e85e3a7f25691f9bf47bec490f3e6be8e461305
```

Consumers restore it with:

```yaml
- uses: qigao/vcpkg-cache/.github/actions/setup-re2c-tools@v0.1.5
  with:
    version: "4.6.7"
    sha256: "fe3c64ef3c25a28a9e5143bf2e85e3a7f25691f9bf47bec490f3e6be8e461305"
```

Omitting both inputs selects the same explicit published lock. Overrides must
supply both `version` and `sha256`; a single override fails before download.
The reader does not select the latest version, accept a version wildcard, or
fall back after a failed restore. It verifies the whole nupkg digest, unique
package identity, safe member paths, native binary and nonempty C syntax /
Unicode data before extracting or executing payloads. Only a successful
`--version` run publishes `RE2C_ROOT`, `RE2C_PACKAGE_VERSION`,
`RE2C_PACKAGE_SHA256` and the binary search path. Use a fresh destination.

The 4.6.7 archive was published from
[producer commit 63b29115780a01f429e23cbba791ca40c779b26e](https://github.com/qigao/vcpkg-cache/commit/63b29115780a01f429e23cbba791ca40c779b26e)
in [run 41263215892](https://github.com/qigao/vcpkg-cache/actions/runs/41263215892).
Its actual Ubuntu 22.04 and 24.04 verification receipts and the successful
publisher agree on the digest above. The package producer includes Linux,
macOS and Windows x64/ARM64 hosts to build every published payload.

For historical comparison, the 4.6.4 package
(`9e1eb668eb818e81c6ba50d9342f874247b2ea66f33a00d2e253053ef1474269`)
contains Linux x64/ARM64, macOS ARM64 and Windows x64 payloads, with no macOS
x64 payload. Its Linux x64 binary requires `GLIBCXX_3.4.32` and cannot run on
the affected Ubuntu 22.04 host.

The direct CLI requires both arguments, with no implicit version selection:

```sh
python scripts/github-packages.py re2c "$RUNNER_TEMP/qigao-re2c-binary" \
  --version 4.6.7 \
  --sha256 fe3c64ef3c25a28a9e5143bf2e85e3a7f25691f9bf47bec490f3e6be8e461305
```

## Workflows

Allowed workflows in this repository are infrastructure workflows only:

- `lemon-tools-package.yml` — builds, packages and publishes the paired `Qigao.Lemon.Binary` host tools.
- `re2c-tools-package.yml` — builds and publishes `Qigao.Re2c.Binary`.
- `curl-only-vcpkg-producer.yml` — manually builds and optionally publishes shared vcpkg ABI packages.

Product SDK packaging and publishing must live in the product repository.
CI workflows build, package and publish infrastructure artifacts; they do not run tests.
