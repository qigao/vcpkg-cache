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

Use either compiler action's `toolchain-file` or the existing
`QigaoVcpkgToolchain.cmake` **product CMake wrapper**. These include
`cmake/QigaoCompilerObfuscation.cmake` during product CMake configuration.
It installs C and C++ compiler launchers for every CMake source compilation
in Release/MinSizeRel/RelWithDebInfo; it does not add a link flag or
change Debug. There are **no target lists** and no downstream
`include()`/`qigao_apply_obfuscation_policy()` calls.

For llvm-mingw, `toolchain-file` and `LLVM_MINGW_TOOLCHAIN_FILE` select
`qigao-product-toolchain.cmake`. The independent `dependency-toolchain-file` /
`LLVM_MINGW_DEPENDENCY_TOOLCHAIN_FILE` select the plain **target** compiler.
The `host-dependency-toolchain-file` /
`LLVM_MINGW_HOST_DEPENDENCY_TOOLCHAIN_FILE` select the **Windows host**
compiler. The x64 host triplet uses the latter, even when building ARM64
target packages on an x64 runner; the ARM64 triplet uses the former.
Both triplets explicitly pass the target/host toolchain path variables into
vcpkg's filtered compiler-detection and port-build environments. Temporary
runner paths are untracked; vcpkg's real compiler/toolchain ABI tracking
must remain enabled. Neither triplet loads a product obfuscation launcher.
Do not use the product entry point as a vcpkg port chainload toolchain.
When pinning these shared triplets, pin the compiler action to the same revision.

The llvm-mingw `cxx` output targets the requested product CPU; `host-cxx`
targets the compiler process CPU and builds the pass plugin. Thus an x64
Windows runner building an ARM64 product still builds an x64 host plugin.
Cross builds on Linux/macOS source-build the host plugin with the runner's
native Clang and LLVM development files.

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
The existing opt-in Windows local-only ABI producer builds both x64 and
ARM64 targets on the Windows x64 runner, using a distinct x64 native host
toolchain for host dependencies. ARM64 cross-compilation does **not**
prove ARM64 native runtime execution; that remains a separate downstream
Windows ARM64 gate. No NuGet publication occurs in this producer.

Publishing immutable packages remains separately opt-in.

