# TRE shared overlay

This port moves TurboScript's TRE dependency into the shared vcpkg infrastructure
so other consumers can use the same engine without depending on TurboScript.
The builtin port in the consumers' current baseline packages TRE 0.8.0; selecting
it would change the engine and public headers during this migration.

## Source and local changes

- Upstream: <https://github.com/laurikari/tre>
- Version reported by the library: 0.9.0.
- Pinned post-release commit: `71bfcaf0af3994384987c6c2679ed7d078ffe189`.
- License: BSD-2-Clause; installed as `share/tre/copyright`.
- `pointer-width-alignment.patch` preserves TurboScript's existing `uintptr_t`
  alignment calculation instead of narrowing pointers to `long` on Windows x64.
- The CMake adapter and configuration templates preserve the former vendor
  build: static PIC library, approximate matching, wide characters, multibyte
  input, and heap-backed matcher workspace. No matcher algorithm is changed.

The upstream `lib/` and `include/` sources at this commit match TurboScript's
former vendor tree, apart from the explicit alignment patch and line endings.
The source archive is downloaded and SHA-512 checked by vcpkg; source copies
and binaries are not committed to this overlay.

## Consumption and validation

Add `tre` to the product's own manifest and use the target documented in `usage`.
The package name and target follow the existing builtin vcpkg port:
`unofficial-tre` and `unofficial::tre::tre`. Static linkage preserves existing
plugin deployment; no additional TRE DLL is required. The generic cache warm
manifest includes this port, while product test coverage stays with consumers.

TurboScript's existing `test_fuzzy` exercises regex, literal and approximate
matching with UTF-8 text through the installed library. Configure, build and
run its normal user presets, then select that CTest test before the full suite.
Local Windows x64 validation built the port's Debug and Release libraries and
passed TurboScript's Release build, all 29 configured CTest tests, and install.
Linux, Android, macOS and shared-feed restoration have not been validated for
this migration.

The cache overlay and TurboScript manifest migration must be deployed together.
Publish the overlay first, then update TurboScript's pinned
`setup-vcpkg-cache` action SHA to a published revision containing this port.
For local port development, a configure can select this checkout's `ports`
directory with `VCPKG_OVERLAY_PORTS`. Rollback restores the
consumer's previous vendor integration and manifest; no persisted user data
or script API changes are involved.
