# Canonical product-side vcpkg toolchain, not a third-party vcpkg port
# toolchain. Package dependency ABI and source compiler obfuscation are separate.
set(VCPKG_APPLOCAL_DEPS OFF CACHE BOOL "" FORCE)
if(NOT DEFINED ENV{VCPKG_ROOT} OR "$ENV{VCPKG_ROOT}" STREQUAL "")
  message(FATAL_ERROR "VCPKG_ROOT is required")
endif()
if(WIN32 AND
   DEFINED VCPKG_TARGET_TRIPLET AND
   VCPKG_TARGET_TRIPLET MATCHES "^qigao-(x64|arm64)-windows-llvm-mingw$" AND
   DEFINED ENV{QIGAO_VCPKG_WINDOWS_HOST_TRIPLET} AND
   NOT "$ENV{QIGAO_VCPKG_WINDOWS_HOST_TRIPLET}" STREQUAL "" AND
   NOT DEFINED VCPKG_HOST_TRIPLET)
  set(VCPKG_HOST_TRIPLET "$ENV{QIGAO_VCPKG_WINDOWS_HOST_TRIPLET}" CACHE STRING
      "Canonical Qigao Windows host triplet" FORCE)
endif()
# The product must use the target compiler; vcpkg ports independently
# chainload the plain target/host compilers from their LLVM-MinGW triplets.
if(DEFINED VCPKG_TARGET_TRIPLET AND
   VCPKG_TARGET_TRIPLET MATCHES "^qigao-(x64|arm64)-windows-llvm-mingw$")
  if(NOT DEFINED ENV{LLVM_MINGW_TOOLCHAIN_FILE} OR
     "$ENV{LLVM_MINGW_TOOLCHAIN_FILE}" STREQUAL "")
    message(FATAL_ERROR "Windows product requires setup-llvm-mingw target toolchain")
  endif()
  include("$ENV{LLVM_MINGW_TOOLCHAIN_FILE}")
endif()
if("$ENV{QIGAO_OBFUSCATOR_ENABLED}" STREQUAL "true")
  if(NOT DEFINED ENV{QIGAO_COMPILER_OBFUSCATION_CMAKE} OR
     "$ENV{QIGAO_COMPILER_OBFUSCATION_CMAKE}" STREQUAL "")
    message(FATAL_ERROR "obfuscator: true requires compiler setup module")
  endif()
  include("$ENV{QIGAO_COMPILER_OBFUSCATION_CMAKE}")
elseif(QIGAO_COMPILER_OBFUSCATION_ENABLED)
  message(FATAL_ERROR "Protected product cache reused without obfuscator setup")
endif()
include("$ENV{VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake")
