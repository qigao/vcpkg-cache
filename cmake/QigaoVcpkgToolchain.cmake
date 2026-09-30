# Canonical Qigao development/test vcpkg toolchain.
#
# Dependency resolution belongs to configure/build. Runtime deployment belongs
# to an explicit run/package stage and is never injected into target link steps.

set(VCPKG_APPLOCAL_DEPS OFF CACHE BOOL "" FORCE)

if(NOT DEFINED ENV{VCPKG_ROOT} OR "$ENV{VCPKG_ROOT}" STREQUAL "")
  message(FATAL_ERROR "VCPKG_ROOT is required")
endif()

if(WIN32 AND
   DEFINED ENV{QIGAO_VCPKG_WINDOWS_HOST_TRIPLET} AND
   NOT "$ENV{QIGAO_VCPKG_WINDOWS_HOST_TRIPLET}" STREQUAL "" AND
   NOT DEFINED VCPKG_HOST_TRIPLET)
  set(VCPKG_HOST_TRIPLET "$ENV{QIGAO_VCPKG_WINDOWS_HOST_TRIPLET}" CACHE STRING
      "Canonical Qigao Windows host triplet" FORCE)
endif()

include("$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
