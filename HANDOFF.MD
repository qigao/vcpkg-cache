# Handoff

## 2026-11-01 re2c host package coverage

- A workflow matrix must also be reflected in the package payload admission
  list. The former macOS job ran only on ARM64 while its staging code appeared
  to support x64, so `macos-x64` was never produced.
- Build tools execute on the runner host, not the product target. Keep distinct
  native payloads for Linux, macOS and Windows x64/ARM64; do not map an absent
  host RID to a different architecture.
