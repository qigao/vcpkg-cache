# Protected product Release: compiler-owned obfuscation

The `SENSITIVE_TARGETS`/`ORDINARY_TARGETS` system is deleted.
Downstream products enable the one upstream pass at compiler setup:

```yaml
with:
  build-type: Release
  obfuscator: "true"
```

Linux x64/ARM64 uses runner native Clang, macOS x64/ARM64 uses
independent installed Homebrew LLVM/Clang. Neither has a global
LLVM version restriction. Windows x64/ARM64 uses fixed llvm-mingw
UCRT only because Windows MinGW uses a separate compiler/toolchain ABI.
Android NDK Clang remains product-owned.

The action uses one pinned `eshard/obfuscator-llvm` Git commit.
Either supply the host pass plugin using `plugin-path`, or let setup
build it with the installed host LLVM CMake development package.
The source-built or supplied plugin is passed through
`cmake/QigaoCompilerObfuscation.cmake` to **every product C/C++ source
compiler invocation** in optimized Release builds. Debug remains
unprotected. There are no target declarations, fallback passes, or
standalone compiler validation CI.

Third-party vcpkg dependencies build in separate toolchains and have
their own cache ABIs. Precompiled imported libraries do not become
obfuscated through final linking. This product compiler setting protects
only code newly compiled through the product CMake graph. Obfuscation
raises reverse-engineering cost but cannot make a shipped App immune.

The product's normal Release workflow must successfully compile and
record `QIGAO_COMPILER_OBFUSCATION_ENABLED:BOOL=ON` from its CMake cache
before packaging. A missing LLVM dev SDK, plugin or real Clang plugin
load is a hard failure, not permission to use GCC/MSVC/AppleClang or
publish an unprotected Release. No new installer/consumer/probe CI.

Historic MSVC v145 triplets were deleted. The new Windows
llvm-mingw x64/ARM64 dependencies must use their own UCRT package ABI;
old MSVC cache binaries must not be relabeled.
