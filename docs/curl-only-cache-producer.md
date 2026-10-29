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

## Core ARM64 source proof and read-only availability

`.github/workflows/core-arm64-cache-source-proof.yml` is a separate, **read-only**
qualification workflow. It has no package write permission or upload operation,
and does not add a package set to the protected publisher above. Its pull-request
paths cover its own workflow, proof code, fixed manifests and tests. A re2c-only
repair does not trigger this cache qualification. Manual dispatch requires the
exact infrastructure workflow commit in `expected_source_sha`.

The frozen inputs in `cache-contracts/salts-core-arm64/` reproduce Core commit
`55e4275e7b8920ee58e5574bcda329aee1308b01`. Both product manifest files retain their
original Git blob bytes. `source-lock.json` records the four unavailable exact
package versions, the complete 14-package SDK graph, and the original job links.
The verifier independently pins that lock and the manifest blobs; changing an ABI,
dropping a dependency, changing a triplet or repointing the source is a failure.

The proof uses native `ubuntu-24.04-arm`, target/host `arm64-linux`, and features
`simd,usb,playback,capture,zstd`. It isolates ABI infrastructure
`7bb5b556a001bc82d2922a04a718e986a7f47f54`, including its scripts, overlays and
contract revision `07d8fa1d31497569a71781b6b64fb772c0dba4634cb0d0ecf48024ddd4aa2a56`.
It must run on a revision containing the exact-version re2c reader: the historical
host input is `Qigao.Re2c.Binary/4.6.4`, SHA256
`9e1eb668eb818e81c6ba50d9342f874247b2ea66f33a00d2e253053ef1474269`.
The newer repository's overlays and floating package lookup are not used.

Two jobs keep source proof and remote availability distinct:

1. `source-proof` first issues authenticated GETs for the four exact targets with
   this upstream workflow's read token. `availability.json` records `available` or
   `unavailable_to_workflow_token_404`; a 404 means **absent or inaccessible**, with
   that distinction unresolved. An HTTP/metadata error fails. An observed 404 lets
   source diagnosis proceed, but does not qualify remote availability. The job
   then derives the exact plan in a fresh install root, builds all 14 dependencies
   into an empty write-only files cache, and rechecks the plan in another fresh
   root. Real cache ZIP `CONTROL`/`BUILD_INFO`, archive hashes and native payload
   hashes are retained. The executable bootstrap helpers must match the pinned
   Git objects, the actual canonical contract must match, and copied overlay
   bytes must equal the isolated input. A whole-repository text-normalization
   status is not a substitute for these checks.
2. `fresh-read-back` runs on a separate runner. It downloads only the same-run
   source metadata, never the source cache. With the same input pins it recomputes
   the 14-package plan, fetches every immutable package using curl, and requires
   `vcpkg install --only-binarycaching`. A missing package remains **RED**. The source
   receipt must match this workflow run, infrastructure commit and all 14 exact
   package identities. Each retrieved payload is compared with that actual source
   build; differing payload and ZIP hashes are recorded per package as a separate
   reproducibility observation. An already-published ABI does not promise a
   byte-reproducible rebuild, so such differences are not labelled cache misses.
   This read-only comparison does not approve immutable publication: the existing
   protected publisher still rejects payload conflicts for an immutable version.
   The reader cannot use a source build to repair a miss or accept a different ABI.
   Diagnostics are uploaded on failure.

Upstream-token availability does not establish `salts-core` token access. If these
exact versions are readable upstream while Core cannot read them, an administrator
must check package Actions access and repeat the original Core request. If they
remain unavailable, a package administrator must determine existence before any
separately reviewed production/publication work. Neither outcome authorizes this
workflow to publish. Even a successful source build and binary read-back do not
qualify Core's original source/function migration or release admission.
