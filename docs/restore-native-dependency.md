# Shared package and tool restore

`scripts/restore-native-dependency.py` is the common entry point for local
development and `.github/actions/setup-native-dependency`. It reuses the existing
authenticated GitHub Packages curl transport and the compiler setup's public
curl downloader and archive extractor. It does not run NuGet, .NET or Mono.

These entry points are available in **v0.1.002**. `v0.1.0` does not contain them.
Downstream workflows select `@v0.1.003`; complete source checkouts select
`ref: v0.1.003` for the paired Lemon helper and offline archive support.
Candidate validation may select an exact commit before a release.
Existing release tags stay immutable.

## Source and ownership

| Source | Selection | Authentication | Formats |
| --- | --- | --- | --- |
| `package` | qigao package ID and exact NuGet version | `GH_TOKEN` or `GITHUB_TOKEN` with package read access | `.nupkg` |
| `url` | Explicit public HTTPS URL on `github.com` or `raw.githubusercontent.com` | None; tokens are not sent | `.zip`, `.tar.xz` |

Both require the SHA-256 of the **whole archive**. Package hashes are checked
before opening the ZIP. Public archive downloads use the existing download
size/deadline/redirect-host bounds. Hash mismatches, unavailable versions and
invalid archives fail. Restoration never selects a newer version or falls back.
The separate explicit `resolve` operation below can discover the latest stable
SDK/tool package and freeze its selected bytes into a lock.

The product owns the lock (ID/version or URL plus hash), host/target choice,
SDK layout and CMake target validation. A shared restore is not an ABI or SDK
qualification. Keep using `setup-vcpkg-curl-cache` for native vcpkg ABI restores,
`setup-re2c-tools` for its complete re2c-specific checks, and the compiler setup
actions for compiler selection. This helper does not introduce another product
dependency graph, package publisher or cache prewarming workflow.

## Local CLI

Use Python 3.12+ and curl, from a checkout of this repository. Keep the helper
scripts together; the CLI imports its sibling transport and extraction modules.
For example, restoring the currently documented locked re2c package for a Linux
x64 host:

```sh
python scripts/restore-native-dependency.py package Qigao.Re2c.Binary 4.6.7 \
  --sha256 fe3c64ef3c25a28a9e5143bf2e85e3a7f25691f9bf47bec490f3e6be8e461305 \
  --destination ./dependencies/re2c \
  --payload tools/linux-x64 \
  --require share/re2c/stdlib/syntax/c \
  --require share/re2c/stdlib/unicode_categories.re \
  --require share/re2c/stdlib/unicode_properties.re \
  --executable bin/re2c
```

For a public tool, read the URL and hash from the product's committed lock:

```sh
python scripts/restore-native-dependency.py url "$TOOL_ARCHIVE_URL" \
  --sha256 "$TOOL_ARCHIVE_SHA256" \
  --destination ./dependencies/tool \
  --payload "$TOOL_PAYLOAD_DIRECTORY" \
  --require "$TOOL_REQUIRED_FILE"
```

`--payload` defaults to the archive root (`.`). Host and target directories are
explicit: no host architecture detection or alternate-payload fallback occurs.
`--require` checks a nonempty file relative to the selected payload and can be
repeated. `--executable` additionally grants execute bits for a required file;
setup never executes a restored tool. ZIP executable bits are otherwise
preserved, with setuid and group/world-write permissions removed. Tar archives use the
existing safe extraction filter and allow internal relative symbolic links.
Unsafe paths, special files, case-colliding names and escaping links fail.

The destination must be fresh. Extraction happens in a temporary sibling
directory; a fully checked installation is renamed into place. Failures before
publication remove staging files and emit no Actions exports. Existing
installations are never deleted or replaced; choose a separate versioned
destination to upgrade.

With `--reuse`, an existing local installation is accepted only when its receipt
matches the source, hash, payload and file/path options, and required files are
still present and nonempty. It needs no token or network. This trusts the local
installation receipt; it does not re-download the archive or rehash every
extracted file. A mismatch or missing file fails without replacing anything.

Standard output is a JSON receipt (diagnostics go to standard error). The same
receipt is saved as `<destination>/receipt.json`; extracted files are beneath
`<destination>/payload`. The receipt records source identity, archive hash,
selected root, required files, executable declarations and any PATH additions.
All exported absolute paths use forward slashes on Windows, including UNC
paths, so the receipt and CMake environment do not disagree.

## GitHub Action

Use the published infrastructure version for downstream workflows:

```yaml
permissions:
  contents: read
  packages: read

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-native-dependency@v0.1.003
    id: re2c
    with:
      package-id: Qigao.Re2c.Binary
      version: 4.6.7
      sha256: fe3c64ef3c25a28a9e5143bf2e85e3a7f25691f9bf47bec490f3e6be8e461305
      destination: ${{ runner.temp }}/project-re2c
      payload: tools/linux-x64 # Product selects its actual host/target.
      required-files: |
        share/re2c/stdlib/syntax/c
        share/re2c/stdlib/unicode_categories.re
        share/re2c/stdlib/unicode_properties.re
      executables: bin/re2c
      add-path: bin
      env-prefix: PROJECT_RE2C
```

For public tools, replace `package-id`/`version` with `url`. To consume a committed
lock instead, use `lock-file: cmake/native-sdk.lock.json` and omit
`package-id`/`version`/`url`; the hash is read from the lock. An optional `sha256`
must match that lock. These three source choices are mutually exclusive.
`required-files`, `executables` and `add-path` accept
one path per line, relative to `payload`. The optional `token` input overrides
`github.token` for cross-repository package read access.

The action outputs `root`, `receipt` and `sha256`. With an `env-prefix` it also
exports `PREFIX_ROOT`, `PREFIX_SHA256` and `PREFIX_RECEIPT` for subsequent steps.
`add-path` appends validated directories to `GITHUB_PATH`. The CLI exposes the
same exports through `--github-output`, `--env-prefix` and repeated `--add-path`
options; their corresponding GitHub command files must be present. Local use
without those options needs no GitHub runner environment.

## Explicit latest-package updates

An update job or local maintainer can select the latest **stable SDK/tool
package**, inspect the resulting lock, and commit it:

```sh
python scripts/restore-native-dependency.py resolve Qigao.Re2c.Binary \
  --version latest --output-lock cmake/re2c.lock.json
```

Use `--version 4.6.7` to resolve an exact version instead. The lock records
`schema`, exact source/feed/ID/version and the SHA-256 of the downloaded nupkg.
The latest selection excludes prereleases and compares stable numeric versions;
it does not use textual ordering. Failed updates preserve the previous lock.
The computed digest pins the selected download for later restores; it is not
an independently signed or publisher-supplied checksum. The update is the point
at which the selected version and bytes must be reviewed.

```sh
python scripts/restore-native-dependency.py locked cmake/re2c.lock.json \
  --destination ./dependencies/re2c --payload tools/linux-x64 \
  --require share/re2c/stdlib/syntax/c --executable bin/re2c
```

Normal builds restore the committed lock. They do not query `latest` on every
configure. This avoids CI and local builds selecting different versions during
the same development cycle. Infrastructure Action source releases are a separate
version: downstream still selects a published infrastructure tag containing the
new entry points, independently of the SDK/tool package version.

## CMake

The CLI also accepts `--archive path/to/file.nupkg` for an offline
package source. Its lock hash and NuGet identity are checked before extraction;
it needs no token. The corresponding CMake option is `ARCHIVE_FILE`. This
offline option and the paired Lemon helper are available in `v0.1.003`;
the previous `v0.1.002` tag is unchanged.

Use CMake 3.19+, Python 3.12+ and curl. From a complete, version-pinned checkout
of this infrastructure repository, include the module in the product:

```cmake
include("${VCPKG_INFRA_ROOT}/cmake/QigaoNativeDependency.cmake")
qigao_restore_native_dependency(
  LOCK_FILE "${CMAKE_SOURCE_DIR}/cmake/native-sdk.lock.json"
  PAYLOAD "sdk/${MY_SDK_RID}"
  REQUIRED_FILES "lib/cmake/MySdk/MySdkConfig.cmake"
  OUT_ROOT MY_SDK_ROOT)
list(PREPEND CMAKE_PREFIX_PATH "${MY_SDK_ROOT}")
find_package(MySdk CONFIG REQUIRED)
```

The SDK and its payload paths in this example belong to the product. The helper
does not create imported targets or substitute its own SDK target validation.
Without `DESTINATION`, installations go under
`${CMAKE_BINARY_DIR}/_deps/qigao-native/<lock-and-options-hash>`. A changed lock
or payload uses another directory; repeated configure reuses a matching receipt
and checks required files without downloading. An explicit `DESTINATION` must
be fresh or match the existing receipt exactly.

For host tools, pass `EXECUTABLES "bin/tool"` and use the returned root to locate
the program. `OUT_RECEIPT` optionally returns the receipt file. CMake does not
modify the shell's environment. If CI already restores via the Action, its
exported `PREFIX_ROOT` can instead be passed directly to CMake as a package
prefix; another download is unnecessary.

An explicit CMake update script can call
`qigao_resolve_native_package(PACKAGE_ID Qigao.Re2c.Binary VERSION latest
LOCK_FILE "${CMAKE_CURRENT_LIST_DIR}/re2c.lock.json")`. Keep that call in an
update operation. The same module also works directly in script mode:

```sh
cmake -DQIGAO_PACKAGE_ID=Qigao.Re2c.Binary -DQIGAO_VERSION=latest \
  -DQIGAO_LOCK_FILE=/path/to/re2c.lock.json \
  -P /path/to/vcpkg-cache/cmake/QigaoNativeDependency.cmake

cmake -DQIGAO_LOCK_FILE=/path/to/re2c.lock.json \
  -DQIGAO_PAYLOAD=tools/linux-x64 -DQIGAO_EXECUTABLES=bin/re2c \
  -P /path/to/vcpkg-cache/cmake/QigaoNativeDependency.cmake
```

## Download once before a platform matrix

The existing lock can be downloaded without installing a host-specific payload:

```sh
python scripts/restore-native-dependency.py download cmake/re2c.lock.json \
  --destination build/native-inputs/blobs
```

This writes a SHA-256-named archive, verifies the lock and package identity, and
reuses an existing archive only when its digest matches. Upload the common
`native-inputs` directory as an Actions artifact before starting the matrix.
After each runner receives it, set `QIGAO_PREPARED_INPUTS` to that directory and
use the normal `locked` or `url` restore command. The reader verifies the blob
again and extracts only that runner's requested payload. Missing or corrupt
prepared blobs fail without an external download fallback. Distribution of the
artifact to each independent runner is still necessary.

## vcpkg caches use exact ABI identities

There is no global "latest cache package" that is compatible with every build.
Use `setup-vcpkg-curl-cache` with the product manifest and exact target/host
triplets. Strict remote restoration derives the current ABI set using vcpkg and
downloads those exact packages over curl; CMake then uses the exported
`QIGAO_VCPKG_TOOLCHAIN_FILE` and local files cache.

`restore-packages: "true"` requires every exact remote package and fails when
one is missing. For a normal product build, `restore-packages: "false"` leaves
dependency installation to the product's normal vcpkg build using the local
files cache and pinned source downloads; it does not fetch remote cache misses
automatically. Reusing the newest published binary with a different ABI would
not be a valid fallback. Updating the infrastructure release and updating the
product manifest/baseline are separate explicit operations.

The existing curl qualification workflow tests package restoration through this
action and CMake entry point on Linux x64, macOS x64/ARM64 and Windows x64/ARM64,
using the real locked re2c package and a second credential-free CMake invocation.
Offline tests also exercise latest-to-lock resolution, local reuse and public ZIP/tar.xz downloads with the
transport replaced, SHA failures, archive rejection, fresh destination handling
and receipt/environment path equality. Downstream adoption can follow a new
published `v0.1.003` version without copying another downloader into product repositories.
