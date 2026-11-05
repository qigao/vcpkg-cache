# Native ugrep qualification

`run.py` builds the candidate ugrep overlay from the product manifest baseline,
then invokes its actual packaged executable. There is no linked consumer or
alternative matcher. The workflow uses published `v0.1.5` infrastructure,
runner Clang on Linux/macOS, and LLVM-MinGW on Windows.

The Windows static triplet is separate from the existing dynamic-library
triplet; its PCRE2 dependency and MinGW C++ runtime are linked statically. The
PE import check permits only listed Windows system DLLs. Linux/macOS check the
tool's actual loader dependencies to reject dynamically linked PCRE2/other
non-system libraries. Upstream's POSIX `--enable-static` adds a global `-static`
flag, which also requests a static system runtime and is not a macOS linkage
mode; the recipe retains `--disable-static` and uses the vcpkg static PCRE2
archive. This is a third-party static dependency requirement, not a promise of
a fully static system runtime.

The protocol suite checks literal/PCRE2 separation, required lookbehind,
stdin and UTF-8 offsets, JSON escaping, multiline framing, no-match/error exit
codes, ignored interactive configuration, and bidirectional pipe I/O exceeding
the kernel buffer. It does not qualify FSX's future process ownership,
cancellation, file identity, content API, or bfs traversal.

The custom format includes `%b`, so each match on a line emits its own record
with its own byte offset, even when the line text repeats. Consumers count
records, not unique matching lines. The exact repeated-line behavior is asserted
by the UTF-8 offset case; no grouping assumption is inferred from normal terminal
output.

From a prepared native compiler/vcpkg environment:

```text
TOOL_TRIPLET=x64-linux python3 tests/search-tools/run.py
```

Windows uses `TOOL_TRIPLET=qigao-x64-windows-llvm-mingw-static`; macOS uses
`TOOL_TRIPLET=arm64-osx` on the selected Apple Silicon runner. All profiles
build source with `VCPKG_BINARY_SOURCES=clear` for this qualification. No
release, cache publication, downstream pin update, or feature fallback occurs.
