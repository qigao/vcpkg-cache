# Compiler selection and setup

Windows uses [llvm-mingw 20261020](https://github.com/mstorsjo/llvm-mingw) (UCRT) from a fixed release archive. The shared `setup-llvm-mingw` action downloads this kit, checks the archive digest for download integrity, and exports C/C++ toolchain paths. **It does not test, identify, benchmark or verify Clang**, does not compile smoke executables, and creates no installer/consumer tests.

Linux selects the runner's existing `clang`, `clang++`, `llvm-ar` and `llvm-ranlib` directly from PATH; macOS selects the same LLVM tools from the installed Homebrew formula (`llvm@18` by default, configurable). No compiler version or identity checks are performed. The `setup-llvm-native` action writes a native CMake toolchain file and exports `LLVM_NATIVE_ROOT`, `LLVM_NATIVE_CC`, `LLVM_NATIVE_CXX`, `LLVM_NATIVE_AR`, `LLVM_NATIVE_RANLIB`, `LLVM_NATIVE_TOOLCHAIN_FILE` and `QIGAO_COMPILER_TOOLCHAIN_FILE`; on macOS it also exports the selected SDK as `SDKROOT`. No native LLVM archives are downloaded.

Release binaries use the `obfuscator-llvm` pass supplied by the product through `plugin-path`. The action returns `obfuscator-compile-flag=-fpass-plugin=...` and the selected pass pipeline. The downstream product must apply that compile flag to protected first-party targets. No plugin ABI, IR, version, CPU, source-build or runtime verification is performed in vcpkg-cache. An absent plugin will fail the actual compiler invocation.

GCC is test-only; AppleClang and MSVC are not release compilers. TinyCC stays independent and is not an obfuscated product Release fallback. No special compiler-validation CI or consumer projects live here.
