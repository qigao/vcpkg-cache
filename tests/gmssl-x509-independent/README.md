# Independent installed GmSSL X.509 baseline (issue #200)

This isolated gate measures the **published Registry provider 3.2.0#12**;
it does not modify the port, production TLS, consumers, registry versions or SDKs.
It deliberately does not combine the unreleased P-384 candidate PR #195 with
published-provider results. A missing capability must fail, never become XFAIL.

## Test separation

`generate-fixtures.py` uses test-only cryptography 46.0.4 and deterministic ECDSA
to produce 31 public certificates for 19 cases (7 positive, 12 negative).
Private keys are reproducible TEST identities and are never written or uploaded.
The full corpus has SHA-256
`30f4a68d5d1658e33a6f88395a9d9fceb2930886065730485abada06a9593f67`.
All native jobs consume the same generated fixture artifact. Expiration of the
explicit 2025-2029 test clock window fails rather than disabling time checking.

The independent OpenSSL CLI first checks all cases with `-x509_strict`, explicit
CAfile, no default CApath/CAstore, and `sslserver` purpose. Each negative must
produce the declared verification error, not merely a nonzero process exit.
OpenSSL/cryptography are test tools, never runtime fallback dependencies.

The C11 driver imports **only installed `GmSSL::GmSSL`** and invokes
`x509_certs_verify` on bounded leaf-first DER chains and an explicit trust anchor.
The wrapper implements no certificate verification or hostname policy itself.
CLI/input errors, abnormal exits, timeouts and malformed result JSON cannot pass
negative tests. An always-rejecting provider cannot satisfy positive controls.

The branch CI restores exact 3.2.0#12 with `--only-binarycaching`, records its
receipt and header/library fingerprints, and builds native Linux x64, macOS arm64
and Windows x64/v145 consumers. A cache miss is a packaging blocker, not proof
of certificate rejection; do not add a source-build fallback.

## Coverage and remaining work

Cases cover CA/keyCertSign, pathLen, leaf/CA EKU, validity, trust anchor,
unknown critical/noncritical extensions, DNS name constraints, bad signature,
P-256/SHA-256, P-256/SHA-384 and P-384-issuer/P-256-leaf SHA-384 chains.
This is **not** TLS handshake, SAN reference-identity, revocation, malformed-DER,
all-policy RFC 5280, source-instrumented Sanitizer or six-RID SDK acceptance.
Negative outcomes do not establish a particular GmSSL rejection reason; inspect
raw provider results and keep paired positive controls before attributing fixes.

Local checks require only Python stdlib and OpenSSL after fixture generation:

```sh
python generate-fixtures.py  # optional test-only cryptography==46.0.4
python check.py --oracle --out oracle-report
python -m unittest discover -p test_check.py -v # POSIX harness self-tests
cmake -S . -B build -DGMSSL_INSTALLED_ROOT=/absolute/installed/triplet -DCMAKE_BUILD_TYPE=Release
cmake --build build --config Release
python check.py --provider build/gmssl-chain-driver --out provider-report
```

Keep PR Draft / DO NOT MERGE. No package publication or dependency migration.
References: RFC 5280 sections 4.2 and 6; OpenSSL `openssl-verify` documentation;
qigao/vcpkg-cache issues #200 and #194, and PR #195.
