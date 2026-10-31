# Compiler selection and setup

Windows uses [llvm-mingw 20261020](https://github.com/mstorsjo/llvm-mingw) (UCRT) from a fixed release archive. The shared `setup-llvm-mingw` action downloads this kit, checks the archive digest for download integrity, and exports C/C++ toolchain paths. **It does not test, identify, benchmark or verify Clang**, does not compile smoke executables, and creates no installer/consumer tests.

Linux uses the runner's existing `clang` and `clang++` from PATH. macOS uses the runner's installed independent LLVM via `brew --prefix llvm@18` by default; the `macos-llvm-formula` input may select another runner-provided LLVM formula without version checks. The `setup-llvm-native` action only selects those paths and creates a lightweight CMake toolchain file. No native LLVM archives are downloaded.

Release binaries use the `obfuscator-llvm` pass supplied by the product through `plugin-path`. The action returns `obfuscator-compile-flag=-fpass-plugin=...` and the selected pass pipeline. The downstream product must apply that compile flag to protected first-party targets. No plugin ABI, IR, version, CPU, source-build or runtime verification is performed in vcpkg-cache. An absent plugin will fail the actual compiler invocation.

GCC is test-only; AppleClang and MSVC are not release compilers. TinyCC stays independent and is not an obfuscated product Release fallback. No special compiler-validation CI or consumer projects live here.
