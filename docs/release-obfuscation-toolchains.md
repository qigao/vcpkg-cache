# Protected Release compiler policy

* Windows x64 and ARM64: fixed `llvm-mingw 20261020` / UCRT because the Windows MinGW toolchain is a separate distribution. Archive SHA256 is checked for package integrity, **not to verify Clang functionality**.
* Linux x64 and ARM64: **runner-native Clang/Clang++ with llvm-ar/llvm-ranlib**; no LLVM version requirement or GNU ar fallback.
* macOS x64 and ARM64: **runner-native independent LLVM/Clang**, selected from Homebrew; no LLVM version requirement. Xcode only supplies macOS SDK and system libraries.
* All platforms: `eshard/obfuscator-llvm` plugin is used by the product with `-fpass-plugin`, without an imposed LLVM version, a standalone compiler test suite, IR preflight, ABI/probe matrix or automatic fallback.
* GCC may be used in tests only. MSVC and AppleClang do not build protected Release binaries.

The project consuming the action owns its own actual build, obfuscator plugin installation and published artifacts. This repository no longer produces compiler validation workflows, synthetic consumer/installer projects, Clang version/ABI checks, standalone pass probes or their test suites. The historic LLVM23 host plugin experiments remain recorded in GitHub PR/Issue history but are not constraints on runner-provided Clang.

## Windows llvm-mingw ABI migration

Removed the MSVC `qigao-x64-windows-v145` triplet and introduced x64/ARM64
Windows llvm-mingw/UCRT triplets with explicit compiler chainload.
These must produce separate package ABI records; historical MSVC
packages cannot become MinGW binaries by renaming a cache key.
Neither ordinary dependency compilation nor static linkage
retroactively applies obfuscator-llvm to precompiled code.

Windows llvm-mingw packages are generated through the repository's curl-only
bootstrap into a local write-only ABI files cache. The optional producer
preserves the resulting ZIPs as short-retention workflow artifacts; it does
**not** invoke Mono/nuget.exe or automatically publish immutable packages.
Any remote upload must go through a separately approved curl-native publisher.

## First-party target classification is the release protection boundary

The **product** must review and explicitly classify every first-party compiled
C/C++ target as either `SENSITIVE_TARGETS` or `ORDINARY_TARGETS`, once in
its own `cmake/ProtectionTargets.cmake`. The shared single owner is
`cmake/QigaoFirstPartyObfuscation.cmake` in this repository. Both compiler
setup Actions expose its absolute path as `obfuscation-policy-cmake` and
`QIGAO_OBFUSCATION_POLICY_CMAKE`. The user does not need a new repository,
installer/consumer project, source scanner or a compiler probe CI.

```cmake
# Called AFTER add_library/add_executable definitions in the downstream
# product's ordinary CMake graph, using the action-provided shared module.
include("$ENV{QIGAO_OBFUSCATION_POLICY_CMAKE}")
qigao_apply_obfuscation_policy(
  SENSITIVE_TARGETS product_ai product_license
  ORDINARY_TARGETS product_shell product_logging
)
```

`SENSITIVE_TARGETS` get **PRIVATE** `-fpass-plugin=<provided plugin>`
only while compiling C/C++ source in `Release`, `MinSizeRel` or
`RelWithDebInfo`. Every ordinary first-party target and all third-party
vcpkg dependencies remain unmodified. Debug is never obfuscated. A missing
target, duplicated classification, invalid noncompiled target or an imported
sensitive library is an error. A missing plugin for single-config Release
fails CMake configuration; multi-config Release fails in the actual compiler
invocation, without a silent unprotected fallback. The Actions forward the
product-supplied `plugin-path` to `QIGAO_OBFUSCATOR_PLUGIN_PATH` and keep
the existing `flattening,substitution` pass environment.

A third-party precompiled `.a/.lib/.so/.dll` remains unprotected even if
a linked executable uses a pass plugin; sensitive upstream first-party
libraries must be declared and compiled as protected **in their own owning
repo/target**. Imported sensitive binaries cannot claim protection. Header-only
sensitive source is compiled in its consuming first-party target, so that
compiled target must be classified sensitive. Classification is a product
review responsibility, not something vcpkg-cache can infer by scanning.

The shared module **does not check** Clang versions, LLVM ABI, plugin file
contents, function IR changes, executable runtime, product signing or the
number of compiled protected functions. The normal product compilation is
the only build failure mechanism; the module's target property is a policy
declaration, **not proof** that a binary is resistant to reverse engineering.
