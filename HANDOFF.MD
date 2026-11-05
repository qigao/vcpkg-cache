# Handoff

## 2026-11-01 re2c host package coverage

- A workflow matrix must also be reflected in the package payload admission
  list. The former macOS job ran only on ARM64 while its staging code appeared
  to support x64, so `macos-x64` was never produced.
- Build tools execute on the runner host, not the product target. Keep distinct
  native payloads for Linux, macOS and Windows x64/ARM64; do not map an absent
  host RID to a different architecture.
- A producer test can hide Windows runtime DLL dependencies because llvm-mingw
  adds its `bin` directory to PATH. Link packaged host tools statically and run
  the staged executable with a system-only PATH before packing. The immutable
  4.6.6 package fails clean-reader execution with `0xC0000135`; never republish
  different bytes under that version.
- The published self-contained six-RID 4.6.7 package is immutable and locked by
  full NUPKG SHA-256
  `fe3c64ef3c25a28a9e5143bf2e85e3a7f25691f9bf47bec490f3e6be8e461305`.
  Producer run: `41263215892`; do not substitute an Actions artifact ZIP digest.

## 2026-11-05 GmSSL client identity selection

- TLS 1.2 must track CertificateRequest separately from selected client signing
  credentials: no match sends an empty Certificate and skips CertificateVerify.
- Range-to-TLS1.2 mTLS needs the retained ClientHello in the raw signature
  transcript. TLS1.3's PSS offer must not select TLS1.2's PKCS1-only RSA signer.
- CA hints can name an intermediate issuer. Parse the entire DN vector before
  selection, even when the local signature intersection is empty. Qualification
  belongs to salts-core's formal native/independent TLS CTests.
- The registry intentionally stores only the current GmSSL version entry.
  Replace that entry when bumping the port; appending historical entries fails
  the existing registry contract workflow even when the tree hashes are valid.

## 2026-11-05 independent certificate signatures

- TLS1.3 extension 50 has distinct local values from handshake signatures.
  Carry its context switch into tls13_init and use the certificate list for
  emission, identity selection and both role verifiers. Missing peer extension
  50 inherits the peer handshake list, intersected with local certificate policy.
- Qualification lives in salts-core formal tests: mixed P256/P384 signatures,
  PSS handshake/PKCS1 chain, input erasure and independent standard/SM2 peers.

## 2026-11-05 AES128/192 PKCS8 import

- The general X509 cipher algorithm table already includes all AES CBC OIDs.
  PBES2 import had a second whitelist admitting only SM4 and AES256; extend
  that reader whitelist rather than adding another ASN1 decoder downstream.
- salts-core's formal CTests qualify input bounds, exact cipher key lengths,
  independent RSA/P256/SM2 envelopes and authenticated TLS/TLCP use. AES256
  retains the shared maximum-iteration boundary without repeating that costly
  KDF for every equivalent key-size branch.

## 2026-11-06 certificate time diagnostics

- Record expired/not-yet-valid at the same validity check and clock sample as
  the actual verifier failure. A later certificate rescan can misidentify the
  first failure. Keep the original public x509_cert_check signature as a wrapper.
- Normal, CA-purpose and TLCP verification must preserve specific failure
  results rather than overwrite them with generic certificate errors. Successful
  checks must leave the caller's result unchanged.
- Malformed intervals and failed clock reads retain existing generic results;
  TLS1.2 can reject malformed Certificate data before entering verification.
  Qualification belongs to salts-core's formal native/independent tests.
