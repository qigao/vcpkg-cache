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
- GitHub Packages NuGet V3 index and exact package version are read with authenticated curl; strict package ID, CONTROL ABI, BUILD_INFO and archive member checks precede materialization.
- Strict restoration (the default) requires every exact remote ABI archive, then vcpkg installs from the local files cache. Missing, inaccessible or corrupted packages fail closed.
- Normal product builds select `restore-packages: "false"`: validate the real manifest and triplets, prepare the same tools/local files cache, and let the existing product build install pinned dependencies. Source downloads use curl/libcurl and pinned hashes. This mode does not request remote binary archives or catch restore errors.
- mode: read is supported; readwrite/write intentionally fail until a curl-only producer publisher is separately qualified.

## Usage

Required workflow permissions: contents: read and packages: read.
Add uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-curl-cache@v0.1.002
with mode: read, triplet: x64-linux, host-triplet: x64-linux; manifest-root defaults to the repository root.
For a normal product CMake/vcpkg build, add `restore-packages: "false"`.
Omit it (or select `"true"`) only when every exact binary-cache package is required.
Both modes validate the actual manifest and requested features; the product's
build remains responsible for selecting its own CMake/vcpkg features.
`v0.1.002` includes this curl-only transport. Candidate PR validation can pin its
exact commit; the original `v0.1.0` tag is not rewritten.

Setup exports VCPKG_ROOT, VCPKG_BINARY_SOURCES, VCPKG_BINARY_CACHE,
VCPKG_CACHE_REPOSITORY_ROOT, QIGAO_VCPKG_TOOLCHAIN_FILE and canonical
identity outputs. The binary source is the local files provider only.

The cache-contract revision includes the canonical curl action and its
bootstrap, manifest resolver and package transport scripts. Their content
changes produce a new revision, including this migration from the legacy
action. Consumers must use that identity and its exact package ABIs; the
strict restore must not substitute an older cache identity or fall back on a miss.
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
to obtain pkg-config. A port that explicitly requires Bash, Autotools or other
MSYS2 utilities still has its own build requirements. Linux and macOS continue
using their native pkg-config. Existing action SHA pins or tags must be updated
to `v0.1.002` to receive it; earlier published tags are unchanged.

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
