# Shared vcpkg cache production

The manual `curl-only-vcpkg-producer.yml` workflow builds dependencies from this
repository's root `vcpkg.json`, using the pinned vcpkg scripts, shared overlays
and compiler setup actions. It runs no unit tests, generated-code tests, smoke
checks or consumer projects.

## Dispatch

In GitHub Actions, select **Build and publish shared vcpkg cache (curl-only)**
and **Run workflow** on `master`:

- `platform`: defaults to `all`, building all profiles in one workflow run
  with parallel matrix jobs. Select one platform for an isolated build.
- `publish`: defaults to `false`. The build saves native ABI ZIPs and their exact
  package plan as an artifact. Set `true` to publish the same archives to GitHub
  Packages after the build succeeds.

| Platform | Runner | Target and host triplet |
| --- | --- | --- |
| `linux-x64` | `ubuntu-24.04` | `x64-linux` |
| `linux-arm64` | `ubuntu-24.04-arm` | `arm64-linux` |
| `macos-x64` | `macos-15-intel` | `x64-osx` |
| `macos-arm64` | `macos-15` | `arm64-osx` |
| `windows-x64` | `windows-2025` | `qigao-x64-windows-llvm-mingw` |
| `windows-arm64` | `windows-11-arm` | `qigao-arm64-windows-llvm-mingw` |
| `windows-msvc-x64` | `windows-2025` | `x64-windows` |
| `android-arm64` | `ubuntu-24.04` | target `arm64-android`, host `x64-linux` |
| `android-x64` | `ubuntu-24.04` | target `x64-android`, host `x64-linux` |

The matrix runs inside one Actions run, with per-platform concurrency and
independent cache/artifact names. Failed jobs can be retried without rerunning
successful jobs. A preceding preparation job downloads the pinned vcpkg Git
history, vcpkg executables, compiler archives, host tools and reference port
sources once, verifies their hashes and uploads one shared input artifact.
Preparation uses the existing reference manifest with `--only-downloads`;
it does not compile dependencies. Matrix jobs consume that artifact through a
read-only local asset cache with origin downloads blocked. A missing or corrupt
input fails the job instead of downloading it again. Actions still distributes
the artifact to each runner because hosted runners have independent disks.
Verified preparation downloads are cached for retries; compiler installations
and platform build trees remain local to their owning matrix job.

Unix uses the shared native Clang setup;
Windows uses the pinned llvm-mingw/UCRT setup, except the explicit MSVC profile,
which uses the image's Visual Studio. Android uses the image's installed NDK.
The reference manifest also includes libyuv and libjpeg-turbo on Windows,
Linux and Android. The producer restores and saves
its downloads and native ABI archives with Actions cache. Its files provider
is read/write: exact ABIs are reused and missing ABIs are built from source. There are no
automatic scheduled or push-triggered cache builds.

## Publication settings

The build job has `packages: read`. The optional publication job alone has
`packages: write` and uses the existing `native-cache-publish` environment.
Keep the environment's required reviewers configured and set its
`NATIVE_CACHE_PUBLISH_ARM` secret to `native-cache-publish-v1`, as required by
the previous native publisher. The workflow fails explicitly if the setting is
absent.

The publisher uses authenticated curl and the existing NuGet V3 transport.
It does not run Mono, `nuget.exe` or `dotnet restore`. It checks artifact
checksums, canonical vcpkg package IDs and full ABI versions before uploading.
Existing identical native payloads are reused; a conflicting immutable version
fails. A new upload must pass the publisher's exact archive readback before it
reports success. This is part of publishing, without a separate CI test job.

Artifacts are named `vcpkg-cache-<platform>-<run-id>` and retained for 14 days.
They contain the native `cache/` ZIPs, vcpkg-generated `packages.config`,
`source.json` with the infrastructure revision and triplets, and `SHA256SUMS`.
Source builds do not receive a package write token.

The release artifact also contains `installed-<triplet>.tar.xz`: the complete
preinstalled reference dependency tree rooted at `vcpkg_installed/`. Its hash,
size and payload root are recorded in `cache-<triplet>.json`, alongside the
exact ABI packages and source provenance. This generic dependency archive is
not a product SDK. Consumers that prohibit vcpkg/toolchain execution can
download a qualified archive with the shared SHA-256 restore helper and point
their presets at its installed tree. They retain their own manifests, compiler
selection and runtime qualification; extraction does not resolve new ABIs.

## Downstream reuse

Use `setup-vcpkg-curl-cache` with the downstream application's own manifest,
triplets and features. A shared archive is reusable only when vcpkg resolves
the same complete ABI. Match the infrastructure overlays and compiler inputs;
publishing the reference manifest cannot guarantee coverage for a product's
different dependency graph or feature selections.

The default `restore-packages: "true"` restores listed exact ABIs from the
v0.1.2 binary release. Unlisted ABIs are normal cache misses: the application's
regular build compiles them and saves its files cache. Authentication, TLS,
hash, archive and published-asset failures remain fatal.
`restore-packages: "false"` explicitly skips remote binary restoration.
Product-specific dependency graphs and their cache producers remain owned by
the product repository.
