# Handoff

## 2026-11-01 re2c host package coverage

- A workflow matrix must also be reflected in the package payload admission
  list. The former macOS job ran only on ARM64 while its staging code appeared
  to support x64, so `macos-x64` was never produced.
- Build tools execute on the runner host, not the product target. Keep distinct
  native payloads for Linux, macOS and Windows x64/ARM64; do not map an absent
  host RID to a different architecture.
- The published six-RID 4.6.6 package is immutable and locked by full archive
  SHA-256 `9f5207934a16124345e43d9b286cbbdd53a3816fcb8cf20d755ff30012597aaf`.
  Producer run: `41262313227`; do not infer this digest from an Actions artifact
  ZIP digest or from an earlier dry-run build.
