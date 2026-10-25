# GmSSL 3.2.0#13 → standalone Crypto provider: source handoff

This directory stages a **byte-for-byte, source-identical migration kit**.
It does **not** move the port, create a new GitHub repository, modify the
installed GmSSL package, switch production CNet, or authorize a release.

## Frozen source identity

- vcpkg registry repository/commit: `qigao/vcpkg-cache@2e214ae44a3e3244eded5db6361194576356fc9e`
- vcpkg port tree: `8e8fda20b723803adc53613f6f608736238ac97d`
- port: `gmssl 3.2.0#13` (versions/g-/gmssl.json and baseline.json unchanged)
- GmSSL upstream source: `guanzhi/GmSSL@7c9f02904ef33e59c87b4f16621cc8fd434e7579`
- upstream GmSSL license: Apache-2.0, copied verbatim from the pinned source

The machine inventory is `ownership-manifest.json`. It lists **all 95
tracked files** with original Git blob IDs, proposed destination and
per-file ownership group. Exactly **3** packaging/registry files stay in
vcpkg-cache; **40** source patch scripts, **13** source/header/backport
files and **39** conformance/fixture files transfer to Crypto. The two
source patch classes contain the original GmSSL TLS/X.509/ASN.1, RSA,
AES key wrap, P-384, Provider External-I/O, fatal alert and ABI
adaptations. Weak MD5/DES compatibility additions are included for
historical parity but must not be enabled as new Crypto public defaults.

## Reproducible export without GitHub tokens or patch application

On the exact source branch (or its PR merge ref):

```bash
python3 tools/verify_gmssl_crypto_handoff.py
python3 tools/verify_gmssl_crypto_handoff.py \
  --export gmssl-provider-handoff.tar.gz \
  --report gmssl-provider-handoff.json
tar -tzf gmssl-provider-handoff.tar.gz
```

The exporter verifies all 95 *Git blob identities*, upstream source
commit, port static-provider contract, all 40 source patch entries,
`versions/baseline.json`, the registry port version/tree and the
original Apache-2.0 license. It is network-free and exports bytes from
`git cat-file`, **not from a mutable working tree**. The resulting
deterministic tarball contains **92 provider source/patch/test files**
plus a provenance manifest, handoff README and license (95 entries).
The 3 vcpkg packaging files are intentionally excluded. CI produces
two archives and asserts identical SHA-256 before uploading the
content-addressed handoff artifact.

Target layout **once the standalone `qigao/crypto` repository exists**:

```text
providers/gmssl/patches/       40 source patches + 13 source/backports
providers/gmssl/tests/         39 original C11/TLS/X.509/interop tests
providers/gmssl/LICENSE
providers/gmssl/README.md
providers/gmssl/provenance/ownership-manifest.json
```

**Important:** this is an exact **input kit** for the independent
Crypto/GmSSL fork/provider, not an already patched/buildable GmSSL
source checkout. The original `vcpkg_replace_string` scripts use
`SOURCE_PATH` and their own `CMAKE_CURRENT_LIST_DIR`; their
relative sibling layout is preserved inside `patches/`, but Crypto
must assemble/review them against the pinned upstream source and
run the original suite before claiming a provider release.

## Strict ownership and release gates

**Crypto owns:** a reviewed, pinned GmSSL fork or prepared source tree,
cryptographic primitive extensions, TLS 1.2/1.3/X.509/External-I/O and
Provider ABI/lifetime contracts. The public Crypto API must use opaque
provider contexts and bounded C11 ownership. CNet consumes Crypto and
must never statically embed a second GmSSL binary owner.

**vcpkg-cache retains:** `ports/gmssl/portfile.cmake`, `vcpkg.json`,
`GmSSLConfig.cmake`, registry versions/baseline, package-install
smokes and binary cache. The current **3.2.0#13** port/tree must remain
intact throughout this handoff. Only after Crypto independently
qualifies all original code/tests on Linux, macOS, Windows and
Sanitizers may vcpkg-cache replace its dozens of source-adaptation
patches with a fixed, reviewed Crypto/GmSSL source commit; that
change requires a **new port-version** and updated registry git-tree.

No OpenSSL fallback, no silent TLS capability loss, no dual owner,
no release without independent CA/SAN/TLS/P-384 interoperability
results. See [vcpkg-cache issue #207](https://github.com/qigao/vcpkg-cache/issues/207),
[SaltsCore owner issue #20](https://github.com/qigao/salts-core/issues/20)
and [Salts migration #1287](https://github.com/qigao/salts/issues/1287).

## Blocking external action

A standalone `qigao/crypto` repository does not yet exist in the
connected account's repository list. The GitHub integration here
cannot create a repository. It must first be created on GitHub
before this verified tarball can be imported or turned into a
Crypto-side PR. Until then, this PR is staging only; retain the
current vcpkg registry and production CNet pins unchanged.
