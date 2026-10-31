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
