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
explicit audited sets: `simde` and `wabt`. It also requires the exact
40-hex `expected_master_sha`; a wrong HEAD, non-master ref or foreign
repository fails closed. `publish=false` is the default.

A live `publish=true` also requires the operator to provide **both**
`expected_native_id` and `expected_native_version`, with the complete,
64-lowercase-hex vcpkg ABI suffix. For the missing WABT package tracked in
[Issue #230](https://github.com/qigao/vcpkg-cache/issues/230), enter:

- `package_set=wabt`, `expected_native_id=wabt_x64-linux`
- `expected_native_version=1.0.42-vcpkgcbc2c2ae595865ddfbb317e7822e4f81633cb5dae4103085140643d7fb77f946`

The canonical source-build ABI plan must include exactly that ID/version,
checked **before** staging artifacts and checked **again after approval**.
The operator-specified identity is captured in `source-proof.txt` and
covered by the artifact SHA256 manifest. A different ABI is rejected even
when it came from an otherwise successful WABT source build. For
read-only exploratory `publish=false` dispatch, these two inputs can remain
empty; supplying one without the other fails closed.

Three **separate jobs** enforce least privilege:
1. `native-producer` has only `packages:read`. It compiles from an empty
   local files cache with `VCPKG_BINARY_SOURCES=clear;files,...,write`
   (never from NuGet). The canonical vcpkg executable derives the exact
   package ID/ABI manifest. Offline NuGet package preflight, SHA256 manifest,
   source SHA and native ABI ZIPs are saved in a same-run artifact.
2. `native-publish` runs **only** when `publish=true`, only after a
   successful source build, and uses the `native-cache-publish` GitHub
   Environment with isolated `packages:write`. Its first step validates
   the reviewed master SHA and every artifact checksum before calling the
   **single** native `scripts/publish-vcpkg-curl-cache.py` executable.
   `require_new_upload=true` is the default: successful verification of
   previously published packages alone **does not** qualify a new HTTP PUT.
   Set it to `false` only for separately documented idempotent maintenance.
   Repository administrators must configure required reviewers on this
   environment **and an environment-scoped secret** `NATIVE_CACHE_PUBLISH_ARM`
   with the literal value `native-cache-publish-v1` before enabling actual
   uploads. The write job fails closed if this explicit arm is absent.
   Merely naming an environment is **not** proof that approval rules have
   been configured, and a repository-wide secret is not a substitute for
   configuring environment approvals.
3. `read-back` gets only `packages:read` on a fresh GitHub-hosted
   runner. It restores the published immutable ABI using curl and requires
   `vcpkg install --only-binarycaching`, without any source substitution.

The exact downloaded `.nupkg` SHA256 must match the local upload bytes
for **new** publication. Older already-published immutable ABI versions
are independently verified by canonical native payload digest, not silently
replaced by repackaged bytes. A success in a source-only or offline run
never substitutes for the separately approved real server PUT admission.

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
