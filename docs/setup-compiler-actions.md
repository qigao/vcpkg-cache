# Pinned compiler setup actions

Tracking: [Issue #243](https://github.com/qigao/vcpkg-cache/issues/243) and
[Draft PR #244](https://github.com/qigao/vcpkg-cache/pull/244).

**Status**: independent compiler-install actions are being qualified.
A successful setup/compiler smoke is **not** a verified obfuscated product Release.
All Release, MinSizeRel and RelWithDebInfo profiles are currently denied until
the actual obfuscator + native consumer gate exists. Keep PR #244 Draft.

Both composite actions work from a downstream repository via
`uses: qigao/vcpkg-cache/.github/actions/<name>@FULL_REVIEWED_COMMIT`.
Their own action checkout includes the shared immutable lock and Python helper;
downstream projects do not need to clone vcpkg-cache. Actions install into a
**fresh RUNNER_TEMP directory**, refuse preexisting paths and never use an ambient
host compiler as an implicit fallback. Python 3.12 is set up by each action.
Downloaded GitHub release archives and TinyCC's separately pinned `obfus.h`
are independently checked against immutable SHA256 values.

## LLVM-MinGW: Windows C/C++ from Linux, macOS, or Windows hosts

```yaml
permissions:
  contents: read
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - id: llvm
        uses: qigao/vcpkg-cache/.github/actions/setup-llvm-mingw@FULL_REVIEWED_COMMIT
        with:
          version: "20261020"
          target: arm64
          build-type: toolchain-only
          verify-smoke: "true"
      - name: Configure cross-compiled Windows C/C++ application
        run: |
          cmake -S . -B build -G Ninja \
            -DCMAKE_TOOLCHAIN_FILE="${{ steps.llvm.outputs.toolchain-file }}" \
            -DCMAKE_BUILD_TYPE=Debug
          cmake --build build --parallel 2
```

The action exports `root`, `cc`, `cxx`, `ar`, `rc`,
`toolchain-file`, `target-triple`, `version`, `archive-sha256`,
`smoke`, `release-qualified=false` and `obfuscator-installed=false`.
It also exports `LLVM_MINGW_ROOT`, `LLVM_MINGW_CC`,
`LLVM_MINGW_CXX`, `LLVM_MINGW_TOOLCHAIN_FILE`,
`QIGAO_COMPILER_TOOLCHAIN_FILE` and extends PATH with the verified bin dir.

Allowed target values: `x86`, `x64`, `armv7`, `arm64`.
The source lock currently covers Windows x64/ARM64 hosts, Linux x64/ARM64
hosts, and macOS universal x64/ARM64 hosts. Other host architectures fail
instead of selecting a downloaded binary of the wrong architecture.
`verify-smoke=true` compiles a Windows executable, checks the PE machine,
and **executes it only on a genuinely compatible native Windows runner**.
Cross compilation is not claimed to be native target execution.

To consume vcpkg packages, configure the project-owned vcpkg toolchain and
set `VCPKG_CHAINLOAD_TOOLCHAIN_FILE` to the output from this action, using
an **independently qualified LLVM-MinGW triplet**. Do not reuse the canonical
MSVC v145 Windows dependency cache; the two compilers have different ABI/CRT
contracts. The action does not generate or silently rebuild missing vcpkg
packages, and does not set product dependency choices.

The upstream `llvm-mingw 20261020` toolchain is built on LLVM 23.1.4.
`obfuscator-llvm` must be separately built against the **exact loading Clang
host ABI**, configured with a nonempty real pass pipeline, and tested for IR
changes plus semantic/native parity before Release admission. This setup
action intentionally does **not** install a random same-major LLVM plugin
or claim obfuscation is active.

## TinyCC-builder: Windows C and pinned obfus.h

```yaml
jobs:
  tinycc:
    runs-on: windows-2025
    steps:
      - uses: actions/checkout@v4
      - id: tcc
        uses: qigao/vcpkg-cache/.github/actions/setup-tinycc-builder@FULL_REVIEWED_COMMIT
        with:
          version: "2026-10-29"
          target: x64
          build-type: toolchain-only
          verify-smoke: "true"
      - name: Compile a TinyCC C executable
        shell: pwsh
        env:
          TCC: ${{ steps.tcc.outputs.cc }}
          OBFUS_DIR: ${{ steps.tcc.outputs.obfus-include }}
        run: |
          & $env:TCC -I $env:OBFUS_DIR .\\src\\hello.c -o hello.exe
          if ($LASTEXITCODE -ne 0) { throw 'TinyCC compilation failed' }
          & .\\hello.exe
          if ($LASTEXITCODE -ne 0) { throw 'TinyCC program failed' }
```

The action exposes `root`, `cc`, `toolchain-file`, `target-triple`,
`version`, `archive-sha256`, `smoke`, `obfus-header`,
`obfus-include`, `obfuscator-installed=true` and
`release-qualified=false`. It exports `TINYCC_ROOT`, `TINYCC_CC`,
`TINYCC_TOOLCHAIN_FILE`, `TINYCC_OBFUS_HEADER`,
`TINYCC_OBFUS_INCLUDE`, `QIGAO_COMPILER_TOOLCHAIN_FILE`, and PATH.

The 2026-10-29 Windows portable TinyCC-builder release is pinned with its
SHA256 digest. It includes native `tcc.exe` and `i386-win32-tcc.exe`, plus
`arm64-win32-tcc.exe` as a **cross compiler**. Use `target: x86`, `x64`,
or `arm64`; only Windows x64 is an admitted TinyCC host in this initial
setup. ARM64 cross compilation verifies the emitted PE machine but cannot
claim native runtime or `obfus.h` support.

TinyCC-builder bundles an `obfh-update.cmd` which downloads an unpinned
current header; **do not run it in CI**. The action downloads
`DosX-dev/obfus.h/include/obfus.h` from an exact source commit and checks
the whole header against a reviewed SHA256. In a first-party protected C
translation unit, include it after all standard and system headers:

```c
#include <stdio.h>
#include <stdint.h>
#define OBFH_DISABLE_ANTIDEBUG 1
#define OBFH_FAKE_SIGNATURES 0
#define OBFH_SEED 123456789u
#include "obfus.h"

/* Protected function definitions follow this include. */
```

Linker-only `-I` use is **not** enough to enable `obfus.h`: protected
functions must actually include the header before their definitions. An
initial CMake C-only toolchain path is emitted but remains downstream-gated
until representative CMake consumers run. Mixed TinyCC/LLVM-MinGW objects
require a separate versioned C DLL ABI rather than unreviewed direct object
linking or cross-CRT resource ownership.

`obfus.h` upstream currently claims only **Windows x86/x64**; a TinyCC
ARM64 compiler binary does not change that. Arm64 Release obfuscation remains
blocked. Do not disable a Release gate on unsupported targets.

## Fail-closed admission contract

- `build-type: toolchain-only` is compiler setup for downstream development
  and qualification, not authorization to publish any product.
- `build-type: Debug` is permitted as an unprotected baseline.
- `build-type: Release`, `MinSizeRel` or `RelWithDebInfo` fails immediately
  at setup until real obfuscator-specific Release validation is implemented.
  A downstream product MUST pass its actual build configuration explicitly;
  omitting the parameter must not be treated as release qualification.
- Missing compiler packages, wrong host/target, corrupted archives, absent
  source header, invalid PE architecture or actual compilation failure stop
  the action without updating environment outputs.
- The installer records compiler identity, source SHA, smoke level, target and
  `release_qualified=false` in `qigao-compiler-install.json`. No compiler
  installation by itself certifies application correctness or IR transformation.

## CI and next required work

`validate-compiler-setup-actions.yml` executes offline archive/security and
policy regression tests, then the actual composite action on Windows,
Ubuntu and macOS. The Windows TinyCC matrix includes x86, x64 and ARM64
cross-machine smoke; the LLVM-MinGW matrix includes real CMake application
cross compilation. Any unrun job/runner or missing native target acceptance
must be reported rather than assumed passed.

Follow-up milestones: confirm action CI on the precise PR head, implement
a host-matched LLVM 23 obfuscator plugin setup and real IR/native proof,
create ABI-separated LLVM-MinGW vcpkg triplets and binary-cache producers,
and finish product-specific Release admission. Do not merge this Draft PR or
flip any downstream production compiler until these criteria are met.
