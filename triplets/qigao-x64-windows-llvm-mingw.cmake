# Windows x64 llvm-mingw UCRT dependency ABI; never alias MSVC v145.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_CMAKE_SYSTEM_NAME MinGW)
# vcpkg invokes compiler detection and port builds inside a filtered
# environment. Explicitly retain the immutable setup action's toolchain paths
# without hashing runner-specific temporary directories into package ABIs.
set(VCPKG_ENV_PASSTHROUGH_UNTRACKED
  PATH
  LLVM_MINGW_DEPENDENCY_TOOLCHAIN_FILE
  LLVM_MINGW_HOST_DEPENDENCY_TOOLCHAIN_FILE)
# This triplet can be the x64 host-tools triplet of an ARM64 target build.
# Always use the host's x64 compiler, not the selected ARM64 product compiler.
if("$ENV{LLVM_MINGW_HOST_DEPENDENCY_TOOLCHAIN_FILE}" STREQUAL "")
  message(FATAL_ERROR "Run setup-llvm-mingw before building x64 MinGW host packages")
endif()
set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE "$ENV{LLVM_MINGW_HOST_DEPENDENCY_TOOLCHAIN_FILE}")

