# GmSSL vcpkg source assembly

## Certificate validity diagnostics, port revision 45

`x509-validity-thread-safe-print.patch` removes the shared `ctime` storage from
`x509_validity_print`. The two dates use caller-owned stack text through POSIX
`ctime_r` or the Windows CRT `ctime_s`, retaining the local time zone, English
ctime layout, labels, indentation and trailing newline. Conversion failures
propagate through the existing error return; unsupported Windows CRT dates are
rejected before its invalid-parameter handler. No public interface, trust/time
validation policy, logging suppression, serialization or allocator change.

The reproducer is salts-core's existing concurrent TLS1.2/TLS1.3 M6 CTest:
[failed TSan job 129546092266](https://github.com/qigao/salts-core/actions/runs/42730173176/job/129546092266).
Focused format/concurrency regression belongs to the consumer's formal Crypto
test suite. Other upstream diagnostic `ctime` callers in OCSP, CRLs and TLS trace
are outside this bounded fix and are not claimed thread-safe.

API contracts: [POSIX ctime](https://pubs.opengroup.org/onlinepubs/9699919799/functions/ctime.html)
and [Windows ctime_s](https://learn.microsoft.com/en-us/cpp/c-runtime-library/reference/ctime-s-ctime32-s-ctime64-s-wctime-s-wctime32-s-wctime64-s).

## Historical source ownership

The `gmssl 3.2.0#16` candidate keeps the GmSSL **package owner** and
source-adaptation pipeline in qigao/vcpkg-cache, but owns **no added
implementation `.c` or `.h` files**. The original upstream GmSSL source
is pinned at `guanzhi/GmSSL@7c9f02904ef33e59c87b4f16621cc8fd434e7579`.

The six optional/bounded native C extensions, six interface headers and
one private TLS 1.3 handshake-reader header are stored byte-for-byte in
[qigao/salts-core](https://github.com/qigao/salts-core)
(`crypto/gmssl-extensions/`), pinned by `portfile.cmake` to exact commit
`720abc55eca41cc7f676d0b5dbb38e8605d091b9`.
A **source-only** pinned fetch stages these files into the upstream checkout
*before building GmSSL*. The port never stores a second implementation
copy. `Salts::Crypto` links `GmSSL::GmSSL` from this installed static
archive and does not compile or archive a separate copy of GmSSL sources.

The 41 previously separate `.cmake` adaptation scripts have been
mechanically consolidated, in unchanged order, into four reviewed phases:
`overlays-01.cmake` through `overlays-04.cmake`. Each phase preserves the
original anchored transformations, source order and failure checks; no
functional crypto source or safety rule was deleted as part of consolidation.

`GmSSLConfig.cmake` and `portfile.cmake` remain package configuration,
the one original `.patch` remains a true upstream patch, and
`tests/` preserves 28 C11 contract test sources, fixtures and interop
scripts: these are **tests, not alternative implementations**.

This is a source/package ownership refactor **only**, versioned as
`gmssl 3.2.0#16` because the port source and ABI hash changed.

**Registry policy:** This repository now lists only the current
`3.2.0#16` port revision in `versions/g-/gmssl.json`, and the default
baseline also selects `#16`. All earlier GmSSL port-version entries were
intentionally removed. This does not rewrite Git history or revoke
previously published binary packages. Consumers explicitly resolving an
older port revision through this registry must update their own dependency
selection; this change does not silently migrate Crypto or production CNet.

Acceptance must include GmSSL native conformance on Linux/macOS/Windows,
Android ABI linkage, source ASan/UBSan/LSan and TSan, custom registry and
cache contracts, and end-to-end Crypto/OpenSSL TLS negative gates before
considering merge. There is no compatibility fallback or DSO.

The source-only extension relocation is a repository/path ownership update;
no upstream algorithm, ordered overlay, feature switch, or native compiler
profile is changed. Do not confuse the source-tree relocation with a
production Crypto/CNet API cutover; its exact dependent HEAD remains gated.
