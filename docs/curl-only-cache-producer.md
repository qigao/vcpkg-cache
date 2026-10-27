# Native vcpkg binary cache publishing: curl-only NuGet V3

This is the producer replacement for `setup-vcpkg-cache` `write/readwrite`
and `warm-cache.yml`. It is separate from the already merged curl-only
consumer (`setup-vcpkg-curl-cache`). It does not install or run Mono,
`nuget.exe`, `dotnet restore`, or `vcpkg` NuGet providers.

## Immutable ABI publication

1. Bootstrap the existing canonical pinned `vcpkg` scripts, tool and overlays.
2. Select an audited product manifest and host/target triplets; compile
   dependencies from native source into an **empty, write-only files L1**.
3. Have the SAME vcpkg executable produce `packages.config` containing
   the package IDs and exact `-vcpkg<64-digit ABI>` versions. The producer
   does not guess port-version-to-NuGet-version conversion.
4. Open every `${ABI}.zip` from L1. Validate canonical Package, Architecture
   and Abi fields in `CONTROL`; require `BUILD_INFO`, no symlinks/path
   traversal, duplicated case-insensitive entries or OPC metadata.
5. Build NuGet `.nupkg` including OPC content types, relationships,
   nuspec ID/version metadata. Check ZIP → NuGet → ZIP byte-level
   **payload equality** before any upload.
6. GET the exact version via authenticated NuGet V3. If already published,
   compare the complete native payload; same content is safe/idempotent,
   different content is a **hard immutable-version conflict**.
7. For a missing package only, an explicit `--publish` opt-in resolves
   `PackagePublish/2.0.0` from the GitHub NuGet V3 service index. It uses
   a multipart HTTP **PUT** with credentials on `curl --config -` stdin
   (never argv or a file), and accepts only a 201/202 response.
8. GET the exact new package after server publication and require the
   reconstructed native payload to match the originating ABI ZIP.
   Missing/ambiguous responses are failures, not successful publication.

NuGet V3 PackagePublish is defined by Microsoft:
https://learn.microsoft.com/en-us/nuget/api/package-publish-resource

## Manual admission (bounded dispatch only)

The workflow `.github/workflows/curl-only-vcpkg-producer.yml` has two
explicit choices: `simde` or `wabt`, and `publish=false` by default.
It runs source builds on Ubuntu x64 and records ABI/payload provenance.
`publish=true` requires workflow `packages:write`, and only then uploads.
A second **fresh GitHub-hosted runner** must restore the exact published
binary with the merged curl-only read action and install with
`--only-binarycaching`. Publishing and consuming do not use the same L1.

PRs never publish: `.github/workflows/curl-only-github-packages.yml`
runs offline negative/security tests and exercises roundtrip/dry-run
against existing immutable GitHub Packages. No secrets appear in argv.

## Remaining migration gates

- Run explicit real `publish=true` on one bounded package with an absent
  exact immutable version and confirm fresh-runner read-back.
- Migrate every existing `warm-cache.yml` producer and read-only contract
  to curl-native workflows, retaining the multi-RID package set.
- Reject any downstream dependency on old `setup-vcpkg-cache` and remove
  that action only after all producers and consumers have exact-head CI.
- Do not downgrade ABI validation or revert to NuGet/Mono as a fallback.

Tracking: https://github.com/qigao/vcpkg-cache/issues/217
