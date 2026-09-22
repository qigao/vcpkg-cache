# Praktor.Native

Praktor's native C SDK is built from `qigao/praktor@master` and published by
`qigao/vcpkg-cache` to the qigao GitHub Packages NuGet feed.

The initial package contains **Linux x64, Release, Ubuntu 24.04, core-only**
(`ENABLE_SCRIPT_ENGINE=OFF`). Windows, macOS, Android and TurboScript-enabled
builds are not included. Package versions use the Praktor CMake version plus
`-ci.<run_number>.<run_attempt>` so a moving master never overwrites a release.
The installed manifest records the actual source commit and dependency versions.

Restore `Praktor.Native` and its exact transitive native SDK dependencies using
NuGet from `https://nuget.pkg.github.com/qigao/index.json`. GitHub Packages
requires a token with package read access. NuGet restores files; it does not
automatically configure native CMake projects.

Set `CMAKE_PREFIX_PATH` to the four restored packages' `sdk/linux-x64`
directories, and set `SALTS_ROOT`, `SALTS_UTILS_ROOT`, and `CHTTP_ROOT` to the
corresponding directories. Supply the shared vcpkg toolchain for third-party
dependencies. Then consume the exported target:

```cmake
find_package(Praktor CONFIG REQUIRED)
target_link_libraries(my_app PRIVATE Praktor::Praktor)
```

At runtime, include the SDK `lib` directories and any shared third-party
dependency directories in the loader search path. This is a native SDK with
external dependencies, not a standalone executable bundle. The publication
workflow restores the finished NuGet package into a separate directory, hides
the original install prefix, then builds and runs `smoke/` against that package.

The `Praktor native SDK package` workflow builds and validates on pull requests
without publishing. On master it publishes only after package restore and the
C ABI workflow execution smoke pass. `workflow_dispatch` also rebuilds current
Praktor master, allowing publication after product changes without changing
this repository. Compilation, packing, restore, or smoke failures block publish.
