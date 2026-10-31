# Compiler setup: opt-in whole-product obfuscation

Both existing compiler Actions expose **one** switch:

```yaml
- uses: qigao/vcpkg-cache/.github/actions/setup-llvm-native@PINNED_COMMIT
  with:
    build-type: Release
    obfuscator: "true"
```

On Windows use `setup-llvm-mingw` with `target: x64` or `arm64`.
The action still accepts `plugin-path` to use an existing host plugin;
with no path supplied it checks out the exact pinned
`eshard/obfuscator-llvm` source and builds `LLVMObfuscator` against the
**selected host LLVM development configuration**. The compiler is not
replaced or version-pinned just to satisfy the plugin. The Windows
llvm-mingw release tag is fixed independently for MinGW/UCRT package ABI.

The host must have the LLVM development config (`llvm-config` and
`LLVMConfig.cmake`), CMake and Ninja to source-build the plugin.
The Windows llvm-mingw distribution may lack the host LLVM development
files; in that case provide a suitable Windows-host `plugin-path` or
install the required host development files. Failure is fatal: no alternate
obfuscator and no silent unprotected Release.

With `obfuscator: true`, the action exports
`QIGAO_OBFUSCATOR_ENABLED`, `QIGAO_OBFUSCATOR_PLUGIN_PATH`,
`QIGAO_COMPILER_OBFUSCATION_CMAKE` and the same pass/seed variables
for Clang. Its `obfuscator-enabled`, `plugin-path`,
`obfuscator-compile-flag` and `compiler-obfuscation-cmake` outputs
remain available for build provenance.

Use the action-provided native `toolchain-file` or the existing
`QigaoVcpkgToolchain.cmake` **product CMake wrapper**. These include
`cmake/QigaoCompilerObfuscation.cmake` during product CMake configuration.
It installs C and C++ compiler launchers for every CMake source compilation
in Release/MinSizeRel/RelWithDebInfo; it does not add a link flag or
change Debug. There are **no target lists** and no downstream
`include()`/`qigao_apply_obfuscation_policy()` calls.

The product launcher never runs in third-party vcpkg port build CMake
processes, which use independent triplets and cache ABIs. Already
compiled `.a/.lib/.so/.dll` binaries are unchanged by linking.
Vendored source compiled *inside the product CMake graph* does follow
its compiler, so non-product dependencies should instead be built
through the separate vcpkg dependency graph.

An existing product build may preserve a CMake cache from a prior
compiler; use a fresh product build directory when switching protected
status. The setup rejects a protected Release with obfuscator disabled.
Real Clang compilation is the fail-fast mechanism: **no** dedicated
Clang version, ABI, IR, smoke or separate compiler validation CI exists.

Windows dependencies use distinct `qigao-x64-windows-llvm-mingw` and
`qigao-arm64-windows-llvm-mingw` triplets with independent UCRT ABI.
Historic MSVC/GCC cached packages cannot be aliased to the new ABIs.
Publishing immutable packages remains separately opt-in.
