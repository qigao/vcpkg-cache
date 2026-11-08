# Curl-only GitHub Packages for native vcpkg consumers

The shared `setup-vcpkg-curl-cache` action is the native package download owner.
The former Mono/NuGet setup action has been removed.

## Invariants

- CI must not install or execute Mono. Native package downloads use curl;
  nuget.exe, dotnet restore and the vcpkg NuGet provider are not download paths.
- The canonical vcpkg tool, scripts, overlay ports and ABI contract remain pinned by this repository.
- Compiler archives, native Windows pkgconf and the Windows vcpkg executable
  share the curl downloader with host allowlists, bounded transfers and SHA256
  verification. Unix vcpkg bootstrap also uses curl.
- A product supplies its OWN vcpkg.json, target triplet and host triplet; infrastructure does not select product dependencies.
- The original vcpkg binary graph is resolved via --dry-run and --x-write-nuget-packages-config before HTTP download.
- Native ABI ZIPs are restored from the immutable v0.1.1 Release index; tool
  packages continue using the existing authenticated NuGet V3 transport.
- Cache-first restoration is the default: validate/reuse local exact ABIs, then
  restore listed Release assets with exact size/SHA-256/native metadata checks.
- Only an ABI absent from the index is a normal miss. The product's existing
  CMake/vcpkg build compiles it and writes the local files cache. Authentication,
  TLS, HTTP, malformed index/archive and ABI errors propagate.
- `restore-packages: "false"` explicitly skips remote binaries while preserving
  manifest/toolchain validation; normal consumers should retain the default.
- mode: read is supported; readwrite/write intentionally fail until a curl-only producer publisher is separately qualified.

## Usage

Required workflow permissions: contents: read and packages: read.
Use `qigao/vcpkg-cache/.github/actions/setup-vcpkg-curl-cache@v0.1.1`
with `mode: read`, the actual `triplet` and `host-triplet`; omit
`restore-packages` to use the cache-first default. The product owns its manifest,
features and install graph. Persist VCPKG_BINARY_CACHE with the repository's
existing Actions cache so locally compiled misses can be reused.

Setup exports VCPKG_ROOT, VCPKG_BINARY_SOURCES, VCPKG_BINARY_CACHE,
VCPKG_CACHE_REPOSITORY_ROOT, QIGAO_VCPKG_TOOLCHAIN_FILE and canonical
identity outputs. The binary source is the local files provider only.

The cache-contract revision includes the canonical curl action and its
bootstrap, manifest resolver and package transport scripts. Their content
changes produce a new revision, including this migration from the legacy
action. Consumers must use that identity and its exact package ABIs; the
restore must not substitute another ABI or hide an unavailable listed asset.
Normal product builds do not require an existing remote package for each ABI.

## Windows pkg-config

The shared curl setup action prepares native pkgconf 3.0.7 from the
[`pkgconf` 3.0.7.post0 wheels](https://pypi.org/project/pkgconf/3.0.7.post0/),
built by [pypackaging-native](https://github.com/pypackaging-native/pkgconf-pypi).
The Windows x64 and ARM64 downloads are about 65 KB and 59 KB. Setup verifies
both archive and executable SHA256 pins in `scripts/windows_pkgconf.py`, then
reads only the standalone executable from the ZIP wheel. It invokes neither
pip nor Windows Installer and installs no Python package or MSYS2 runtime.

Setup selects the runner's host architecture independently of the target
triplet, exports `PKG_CONFIG` as an absolute native executable path, and
preserves it through vcpkg's Windows environment filtering using
`VCPKG_KEEP_ENV_VARS`. Existing retained variables are preserved. The shared
LLVM-MinGW triplets track `QIGAO_PKGCONF_VERSION` in their package ABI without
hashing the runner-specific executable path.

This prevents the pinned vcpkg `PKGCONFIG` helper from downloading MSYS2 just
to obtain pkg-config. The reference manifest also uses native Windows libpq
and tree-sitter CLI ports below. Linux and macOS continue using their native
build tools. Existing Action and registry pins must move to `v0.1.1` to receive
the complete setup; earlier published tags are unchanged.

## Exact re2c host package identity

`setup-re2c-tools` accepts `version` and `sha256` as a pair. With neither
input it selects the explicit published `Qigao.Re2c.Binary` 4.6.7 archive,
SHA-256 `fe3c64ef3c25a28a9e5143bf2e85e3a7f25691f9bf47bec490f3e6be8e461305`.
Supplying exactly one input is an error; a different version cannot inherit
the default digest. Consumers pin the action's source to `@v0.1.002` too.

The direct command has no default lock or latest-version path:

```sh
python scripts/github-packages.py re2c "$RUNNER_TEMP/qigao-re2c-binary" \
  --version 4.6.7 \
  --sha256 fe3c64ef3c25a28a9e5143bf2e85e3a7f25691f9bf47bec490f3e6be8e461305
```

The CLI requires an exact three-component version and 64 hexadecimal digest
digits. Authentication uses `GH_TOKEN` or `GITHUB_TOKEN`; the runner supplies
`RUNNER_OS`, `RUNNER_ARCH`, `GITHUB_ENV` and `GITHUB_PATH`. Tokens remain out of
command arguments and logs.

The complete archive hash is checked before ZIP parsing. Unique NuGet package
ID/version, regular payload files, path safety and nonempty binary,
`stdlib/syntax/c`, `unicode_categories.re` and `unicode_properties.re` are
checked before extraction. Every included host payload is checked and the
requested host must be present. Traversal, symlinks, special files, duplicate
or Windows-collapsing names and file/directory conflicts fail closed.

Extraction and `re2c --version` take place in a temporary staging directory.
The destination must be fresh. Verification or execution failure publishes
neither the destination nor environment changes. On success the reader
exports `RE2C_ROOT`, `RE2C_PACKAGE_VERSION`, `RE2C_PACKAGE_SHA256` and its bin
directory. These re2c checks do not change general vcpkg cache semantics.

The default advanced only after the 4.6.7 package was published from
[producer commit 63b29115780a01f429e23cbba791ca40c779b26e](https://github.com/qigao/vcpkg-cache/commit/63b29115780a01f429e23cbba791ca40c779b26e)
in [run 41263215892](https://github.com/qigao/vcpkg-cache/actions/runs/41263215892).
Actual Ubuntu 22.04 and 24.04 verification receipts and the publisher recorded
the same archive digest above. The actual curl reader job covers Ubuntu
22.04/24.04, macOS Intel/ARM64 and Windows x64/ARM64 against the published package.

The historical 4.6.4 package has SHA-256
`9e1eb668eb818e81c6ba50d9342f874247b2ea66f33a00d2e253053ef1474269` and includes
Linux x64/ARM64, macOS ARM64 and Windows x64. There is no macOS x64 fallback.
Its Linux x64 binary requires `GLIBCXX_3.4.32` and fails on the affected
Ubuntu 22.04 host.

GitHub Releases are separate from GitHub Packages: native SDK NuGet packages
are downloaded using their authenticated NuGet V3 metadata and URL; publicly
released standalone tools are downloaded using immutable GitHub Release assets
and SHA256 verification.

## Downstream migration

The no-Mono requirement applies to every active CI workflow and composite
action. There is no legacy caller allowance. Downstream repositories pinned to
older source versions must move to a released version of the curl-only action
and provide their actual manifest, target triplet and host triplet; changing
this repository does not rewrite their existing immutable pins.

Native package publishing remains a separate explicit curl-only upload phase
with verified immutable package provenance. Source-only jobs can call
`scripts/setup-vcpkg-curl-cache.py` to bootstrap the same canonical tools and
local files cache, then build their own manifest with binary caches explicitly
disabled. They must not manufacture an empty manifest to bypass restoration.

## v0.1.1 binary release production and ownership

The existing manual producer builds the reference dependency manifest once per
native platform (Linux, macOS and Windows x64/ARM64), with the same selected
compilers and triplets used by downstreams. It stages the actual native files
cache ZIPs through the existing publisher's CONTROL/BUILD_INFO/member/ABI
validation. Per-platform indexes retain source SHA, tool/scripts identity,
cache revision and each archive's SHA-256 and size. The final Release combines
indexes from successful runs of one source SHA and attaches those exact ZIPs.
The immutable source tag and index must identify that same commit.

This replaces strict all-or-nothing NuGet restoration for the default native
cache path. Treating an archive 404 as a miss was rejected: it cannot reliably
distinguish absence from denied package access. A published index makes an
unlisted ABI an explicit, authorized source-build case while retaining fatal
errors for listed assets. A second package resolver or compiler fallback is
not introduced. Existing explicit NuGet publication/strict CLI remain available;
Lemon/re2c tool packages and their digest locks are unchanged.

Upgrade both the setup Action and Git registry reference to v0.1.1, with the
exact release commit as the registry baseline. Remove downstream explicit
`restore-packages: "false"` overrides to use shared binaries. Preserve each
product's cache save/restore and normal source build graph. Rollback requires
selecting a still-published source/binary release together; removed tags are
not valid rollback targets. Source caches/SDK install trees are not migrated.
No prewarming dependency or product-owned manifest is imported into this repo.

The first macOS ARM64 producer failed at the official Lua 5.4.8 TLS download;
the source build stayed failed. Shared toolchain setup now seeds its ordinary
vcpkg download cache from the existing original source archive at
`packaging/sources/lua-5.4.8.tar.gz`, locked by SHA-256
`4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae`.
Those bytes match both the [official Lua checksum](https://www.lua.org/ftp/)
and the pinned port's SHA-512. The port still verifies its original SHA-512,
version and source contents. This is an explicit required cache input, not
an automatic alternate download after a TLS failure. Missing/inaccessible or
changed source-cache inputs fail. Lua's original source/license stay in the
unmodified archive, also attached to the same infrastructure release. The
producer and downstream setup keep read-only repository permissions; neither needs draft-release
access or an additional credential to seed its source download cache.

Initial production also found two port contracts requiring repair. Ugrep's
Unix manual alias `ug.1 -> ugrep.1` is materialized as an identical regular
file by the port; the cache's symlink rejection remains strict. The ARM64
MinGW libpq port uses PostgreSQL's existing native Windows setjmp/longjmp
branch instead of the x86-only compiler builtin workaround. The original
x64 workaround stays selected for x64. See the
[upstream ARM64 discussion](https://www.postgresql.org/message-id/amjMVEpTddzOvui5%40nathan).
Port versions advance to ugrep 7.8.5#3 and libpq 16.9#3. Native production
checks compile/package these ports; it does not claim live database runtime
or signal/cancellation qualification for libpq.

Windows dependency builds must not acquire MSYS2. The libpq MinGW port uses
the port-owned native CMake/Ninja frontend build in `ports/libpq/native`.
It compiles PostgreSQL's original sources, detects target headers/functions
with the selected compiler, configures the original public configuration
headers, and keeps the external channel-binding patch and exports table.
The installed library set includes libpq, pgcommon/pgport and ECPG libraries;
the `client` feature builds the client tools from the release's generated C
scanners/parsers. MSVC retains the existing native MSBuild backend; Unix
retains its native Autotools backend. Meson was considered but the requested
backend is plain CMake. No alternate compiler or crypto provider is selected.

The tree-sitter CLI port selects the upstream Windows binary for the Windows
host ABI, including MinGW, and decompresses its checksum-pinned gzip with
native Python. Its former shell/gunzip acquisition required MSYS2 even though
the executable itself did not. Upstream license and distribution hashes are
retained. Neither backend creates a separate verification project.

The producer writes `packages.config` in the actual install invocation so
that the publication plan describes the ABIs that were built. A later dry-run
with a different installed tool state cannot substitute its own ABI plan for
the archives from the original build.
