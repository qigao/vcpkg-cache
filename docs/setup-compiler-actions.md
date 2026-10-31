# Compiler selection and setup

Windows uses [llvm-mingw 20261020](https://github.com/mstorsjo/llvm-mingw) (UCRT) from a fixed release archive. The shared `setup-llvm-mingw` action downloads this kit, checks the archive digest for download integrity, and exports C/C++ toolchain paths. **It does not test, identify, benchmark or verify Clang**, does not compile smoke executables, and creates no installer/consumer tests.

Linux selects the runner's existing `clang`, `clang++`, `llvm-ar` and `llvm-ranlib` directly from PATH; macOS selects the same LLVM tools from the installed Homebrew formula (`llvm@18` by default, configurable). No compiler version or identity checks are performed. The `setup-llvm-native` action writes a native CMake toolchain file and exports `LLVM_NATIVE_ROOT`, `LLVM_NATIVE_CC`, `LLVM_NATIVE_CXX`, `LLVM_NATIVE_AR`, `LLVM_NATIVE_RANLIB`, `LLVM_NATIVE_TOOLCHAIN_FILE` and `QIGAO_COMPILER_TOOLCHAIN_FILE`; on macOS it also exports the selected SDK as `SDKROOT`. No native LLVM archives are downloaded.

Release binaries use the `obfuscator-llvm` pass supplied by the product through `plugin-path`. The action returns `obfuscator-compile-flag=-fpass-plugin=...` and the selected pass pipeline. The downstream product must apply that compile flag to protected first-party targets. No plugin ABI, IR, version, CPU, source-build or runtime verification is performed in vcpkg-cache. An absent plugin will fail the actual compiler invocation.

GCC is test-only; AppleClang and MSVC are not release compilers. TinyCC stays independent and is not an obfuscated product Release fallback. No special compiler-validation CI or consumer projects live here.

## Windows llvm-mingw dependency triplets

The retired `qigao-x64-windows-v145` MSVC triplet was deleted.
`qigao-x64-windows-llvm-mingw` and `qigao-arm64-windows-llvm-mingw`
are separate MinGW/UCRT ABI identities. Run `setup-llvm-mingw`
before vcpkg; its `LLVM_MINGW_TOOLCHAIN_FILE` is chainloaded by
the selected triplet. Compiler tracking remains enabled.
Old MSVC cache versions must not be reused or overwritten.

`warm-cache.yml` has an explicit `workflow_dispatch` opt-in
`warm_llvm_mingw=true` for *real Windows x64 dependency production into a local write-only files cache*.
This is not a new workflow or Clang validation CI. The ARM64 triplet
is available, but it is not automatically produced by an x64 runner.
Third-party packages are not implicitly obfuscated; protect sensitive
first-party source during its actual compilation.

Windows llvm-mingw packages are generated through the repository's curl-only
bootstrap into a local write-only ABI files cache. The optional producer
preserves the resulting ZIPs as short-retention workflow artifacts; it does
**not** invoke Mono/nuget.exe or automatically publish immutable packages.
Any remote upload must go through a separately approved curl-native publisher.
