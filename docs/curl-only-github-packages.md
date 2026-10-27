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

GitHub Releases are separate from GitHub Packages: native SDK NuGet packages
are downloaded using their authenticated NuGet V3 metadata and URL; publicly
released standalone tools are downloaded using immutable GitHub Release assets
and SHA256 verification.

## Migration admission

Do not remove the old Mono/NuGet setup action or change production defaults
until all downstream consumers that use it have been migrated and their exact
CI head is green. Native package publishing requires a separate explicit
curl-only upload phase and verified immutable package provenance.
