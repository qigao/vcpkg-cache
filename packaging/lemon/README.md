# Paired Lemon host tools

`Qigao.Lemon.Binary` packages the Lemon executable and **lempar.c** template
from the same pinned SQLite source commit. This is a host build tool, separate
from SQLite libraries, product SDKs and vcpkg target ABI packages.

This first package is a candidate; no published Lemon package/hash is implied.
The immutable infrastructure tag `v0.1.002` is not changed by this work.

The source pair is pinned by commit and SHA-256 in `source-lock.json` (SQLite
3.54.0, package version 1.0.0). Source downloads, package reads and protected
publication reuse existing curl transports; packing uses Python's ZIP/XML
support. No Mono, dotnet pack/restore or NuGet executable is needed. Linux x64
builds use Ubuntu 22.04 for the older glibc floor. Other supported host RIDs are
Linux ARM64, macOS x64/ARM64 and Windows x64/ARM64. Windows uses llvm-mingw;
Unix uses the runner's selected native Clang.

```text
tools/<host-rid>/bin/lemon[.exe]
tools/<host-rid>/share/lemon/lempar.c
tools/<host-rid>/share/lemon/source.json
```

The source manifest binds the upstream source hashes, SQLite commit/version,
package version, host RID and executable digest. Both producer and CMake check
the pair; an edited template, mismatched binary or wrong architecture fails.
Lemon's `-x` output is not used as a trustworthy SQLite/package version.

## CMake

Once a qualified package is published, use the existing CLI to resolve its
exact package version to a product-owned lock, or use a reviewed producer lock:

```sh
python scripts/restore-native-dependency.py resolve Qigao.Lemon.Binary \
  --version 1.0.0 --output-lock cmake/lemon.lock.json
```

The new module requires an infrastructure release containing it (or an exact
candidate checkout for validation). Keep the full checkout/sibling scripts:

```cmake
include("${VCPKG_INFRA_ROOT}/cmake/QigaoLemon.cmake")
qigao_setup_lemon(LOCK_FILE "${CMAKE_SOURCE_DIR}/cmake/lemon.lock.json"
  HOST_RID "${MY_BUILD_HOST_RID}")
# Exports Lemon::Lemon, LEMON_EXECUTABLE, and LEMPAR.

cmake_add_grammar(MyParser
  GRAMMAR_Y "${CMAKE_CURRENT_SOURCE_DIR}/parser.y"
  LEMON_TARGET Lemon::Lemon
  LEMON_TEMPLATE "${LEMPAR}")
```

`cmake_add_grammar` above is the existing downstream helper, not a new API in
this repository. Plain CMake can use `$<TARGET_FILE:Lemon::Lemon>` with
`"-T${LEMPAR}"` in an `add_custom_command`; list the grammar, `Lemon::Lemon`
**and** `${LEMPAR}` in `DEPENDS`, and quote arguments with `VERBATIM`.
The RID identifies the **build host**, not `CMAKE_SYSTEM_PROCESSOR` for the
target. A Linux x64 build of an Android/ARM target needs `linux-x64` Lemon.
No target executable or system Lemon is selected as a fallback.

`ARCHIVE_FILE` optionally supplies a pre-downloaded nupkg with the same lock;
the shared restore checks its hash and NuGet identity before extraction. It is
used for pre-publication package qualification and works without credentials.
Repeated configure reuses the matching local installation and rechecks the
executable/template hashes. Conflicting imported targets fail explicitly.

## Build, qualify and publish

`lemon-tools-package.yml` builds six native host binaries, packs one nupkg and
emits `lemon.lock.json`/`SHA256SUMS` as the `lemon-binary-nuget` artifact.
Seven reader jobs (including Ubuntu 22.04 and 24.04) restore that exact nupkg
through the CMake module, generate a C11 parser with its paired template,
compile and run it. The parser checks precedence, parentheses and invalid-input
rejection. This is the actual tool package's test, not an SDK installer or
synthetic consumer project. There are no compiler version/probe CI jobs.

Publication requires an explicit manual master dispatch with `publish: true`,
after every packed-reader job passes. It uploads those tested bytes using curl
and requires exact SHA-256 readback; it never overwrites a different existing
version. After publication, the shared generic Action from `v0.1.002` can also
restore the package using `lock-file`, `payload: tools/<host-rid>`,
`required-files: share/lemon/lempar.c`, and the appropriate `executables` input.

SaltsUtils currently builds an in-tree Lemon and passes its own `LEMPAR` to
`cmake_add_grammar`. Switching it to this host package is a separate product
change and requires its existing parser/IDL tests; generation alone does not
prove parser semantic compatibility across SQLite source revisions.
