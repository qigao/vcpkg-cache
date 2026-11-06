# Shared vcpkg cache production

The manual `curl-only-vcpkg-producer.yml` workflow builds dependencies from this
repository's root `vcpkg.json`, using the pinned vcpkg scripts, shared overlays
and compiler setup actions. It runs no unit tests, generated-code tests, smoke
checks or consumer projects.

## Dispatch

In GitHub Actions, select **Build and publish shared vcpkg cache (curl-only)**
and **Run workflow** on `master`:

- `platform`: one of the native platforms below.
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

Each dispatch builds one platform. Unix uses the shared native Clang setup;
Windows uses the pinned llvm-mingw/UCRT setup. The producer uses an isolated,
write-only local files cache to compile packages from source. There are no
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

## Downstream reuse

Use `setup-vcpkg-curl-cache` with the downstream application's own manifest,
triplets and features. A shared archive is reusable only when vcpkg resolves
the same complete ABI. Match the infrastructure overlays and compiler inputs;
publishing the reference manifest cannot guarantee coverage for a product's
different dependency graph or feature selections.

With `restore-packages: "true"`, every required remote ABI must exist.
With `restore-packages: "false"`, the application's regular build installs its
dependencies and writes locally built packages to its local files cache.
Product-specific dependency graphs and their cache producers remain owned by
the product repository.
