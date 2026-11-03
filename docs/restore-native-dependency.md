# Shared package and tool restore

`scripts/restore-native-dependency.py` is the common entry point for local
development and `.github/actions/setup-native-dependency`. It reuses the existing
authenticated GitHub Packages curl transport and the compiler setup's public
curl downloader and archive extractor. It does not run NuGet, .NET or Mono.

This entry point is **unreleased**. `v0.1.0` does not contain it. Validate a
candidate with its exact commit; downstream workflows must select a new
published infrastructure version containing the action before adoption. Existing
release tags stay immutable.

## Source and ownership

| Source | Selection | Authentication | Formats |
| --- | --- | --- | --- |
| `package` | qigao package ID and exact NuGet version | `GH_TOKEN` or `GITHUB_TOKEN` with package read access | `.nupkg` |
| `url` | Explicit public HTTPS URL on `github.com` or `raw.githubusercontent.com` | None; tokens are not sent | `.zip`, `.tar.xz` |

Both require the SHA-256 of the **whole archive**. Package hashes are checked
before opening the ZIP. Public archive downloads use the existing download
size/deadline/redirect-host bounds. Hash mismatches, unavailable versions and
invalid archives fail; there is no latest-version lookup or fallback.

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

Standard output is a JSON receipt (diagnostics go to standard error). The same
receipt is saved as `<destination>/receipt.json`; extracted files are beneath
`<destination>/payload`. The receipt records source identity, archive hash,
selected root, required files, executable declarations and any PATH additions.
All exported absolute paths use forward slashes on Windows, including UNC
paths, so the receipt and CMake environment do not disagree.

## GitHub Action

After a new infrastructure version is published, replace the version placeholder
below with that release. For candidate validation use its exact commit instead.

```yaml
permissions:
  contents: read
  packages: read

steps:
  - uses: qigao/vcpkg-cache/.github/actions/setup-native-dependency@<new-release>
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

For public tools, replace `package-id`/`version` with `url`; these source choices
are mutually exclusive. `required-files`, `executables` and `add-path` accept
one path per line, relative to `payload`. The optional `token` input overrides
`github.token` for cross-repository package read access.

The action outputs `root`, `receipt` and `sha256`. With an `env-prefix` it also
exports `PREFIX_ROOT`, `PREFIX_SHA256` and `PREFIX_RECEIPT` for subsequent steps.
`add-path` appends validated directories to `GITHUB_PATH`. The CLI exposes the
same exports through `--github-output`, `--env-prefix` and repeated `--add-path`
options; their corresponding GitHub command files must be present. Local use
without those options needs no GitHub runner environment.

The existing curl qualification workflow tests package restoration through this
action on Linux x64, macOS x64/ARM64 and Windows x64/ARM64, using the real locked
re2c package. Offline tests also exercise public ZIP/tar.xz downloads with the
transport replaced, SHA failures, archive rejection, fresh destination handling
and receipt/environment path equality. Downstream adoption can follow a new
published version without copying another downloader into product repositories.
