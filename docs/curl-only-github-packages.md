# Curl-only GitHub Packages for native vcpkg consumers

Candidate replacement for the old shared setup-vcpkg-cache action.

## Invariants

- Mono, nuget.exe, dotnet restore and the vcpkg NuGet provider are never invoked by the new transport.
- The canonical vcpkg tool, scripts, overlay ports and ABI contract remain pinned by this repository.
- A product supplies its OWN vcpkg.json, target triplet and host triplet; infrastructure does not select product dependencies.
- The original vcpkg binary graph is resolved via --dry-run and --x-write-nuget-packages-config before HTTP download.
- GitHub Packages NuGet V3 index and exact package version are read with authenticated curl; strict package ID, CONTROL ABI, BUILD_INFO and archive member checks precede materialization.
- vcpkg then installs from local files cache, with no remote NuGet provider and no fallback. Missing or corrupted packages fail closed.
- mode: read is supported; readwrite/write intentionally fail until a curl-only producer publisher is separately qualified.

## Usage

Required workflow permissions: contents: read and packages: read.
Add uses: qigao/vcpkg-cache/.github/actions/setup-vcpkg-curl-cache@PINNED_SHA
with mode: read, triplet: x64-linux, host-triplet: x64-linux; manifest-root defaults to the repository root.

Setup exports VCPKG_ROOT, VCPKG_BINARY_SOURCES, VCPKG_BINARY_CACHE,
VCPKG_CACHE_REPOSITORY_ROOT, QIGAO_VCPKG_TOOLCHAIN_FILE and canonical
identity outputs. The binary source is the local files provider only.

## Exact re2c host package identity

`setup-re2c-tools` accepts `version` and `sha256` as a pair. With neither
input it selects the explicit published `Qigao.Re2c.Binary` 4.6.5 archive,
SHA-256 `dfdcf77dfd36e60500532a3fcc8a1bd32dc2232edeb63e053267a712bc4489ed`.
Supplying exactly one input is an error; a different version cannot inherit
the default digest. Consumers should pin the action's source commit too.

The direct command has no default lock or latest-version path:

```sh
python scripts/github-packages.py re2c "$RUNNER_TEMP/qigao-re2c-binary" \
  --version 4.6.5 \
  --sha256 dfdcf77dfd36e60500532a3fcc8a1bd32dc2232edeb63e053267a712bc4489ed
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

The default advanced only after the 4.6.5 package was published from
[producer commit 4864033d4e4bc70d182df6a33695582ec6fcc968](https://github.com/qigao/vcpkg-cache/commit/4864033d4e4bc70d182df6a33695582ec6fcc968)
in [run 40852170873](https://github.com/qigao/vcpkg-cache/actions/runs/40852170873).
Actual Ubuntu 22.04 and 24.04 verification receipts and the publisher recorded
the same archive digest above. The actual curl reader job includes Ubuntu
22.04 as a feed regression, retaining Ubuntu 24.04, macOS 15 and Windows 2025.
Those reader jobs must still pass against the published package.

The historical 4.6.4 package has SHA-256
`9e1eb668eb818e81c6ba50d9342f874247b2ea66f33a00d2e253053ef1474269` and includes
Linux x64/ARM64, macOS ARM64 and Windows x64. There is no macOS x64 fallback.
Its Linux x64 binary requires `GLIBCXX_3.4.32` and fails on the affected
Ubuntu 22.04 host. Its reader regression fixtures remain unchanged.

GitHub Releases are separate from GitHub Packages: native SDK NuGet packages
are downloaded using their authenticated NuGet V3 metadata and URL; publicly
released standalone tools are downloaded using immutable GitHub Release assets
and SHA256 verification.

## Migration admission

Do not remove the old Mono/NuGet setup action or change production defaults
until all downstream consumers that use it have been migrated and their exact
CI head is green. Native package publishing requires a separate explicit
curl-only upload phase and verified immutable package provenance.
