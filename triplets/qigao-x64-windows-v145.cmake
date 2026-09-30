# Canonical qigao Windows binary-cache ABI.
#
# GitHub's windows-2025 hosted label can temporarily span multiple runner image
# revisions. Pin the actual supported Windows toolset here so binary cache
# identity is based on this reviewed contract instead of the ambient image.
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE dynamic)
set(VCPKG_PROVIDED_FORTRAN ON)

set(VCPKG_PLATFORM_TOOLSET v145)
set(VCPKG_PLATFORM_TOOLSET_VERSION "14.51.36231")
set(VCPKG_CMAKE_SYSTEM_VERSION "10.0.26100.0")

# Compiler tracking is disabled only inside the exact toolset/SDK contract above.
# Any compiler or SDK upgrade must edit this file, which changes the cache
# contract revision and forces a fresh binary-cache population.
set(VCPKG_DISABLE_COMPILER_TRACKING ON)
