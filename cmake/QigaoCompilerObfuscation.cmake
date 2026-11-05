# Product compiler obfuscation is activated once by setup-llvm-native/mingw.
# No sensitive/ordinary target lists and no per-target classifications.
# This module is included only by PRODUCT toolchains, not vcpkg port builds.
include_guard(GLOBAL)

if(NOT "$ENV{QIGAO_OBFUSCATOR_ENABLED}" STREQUAL "true")
  return()
endif()
if(CMAKE_GENERATOR MATCHES "Visual Studio|Xcode|Ninja Multi-Config")
  message(FATAL_ERROR
    "obfuscator: true requires a single-configuration product generator")
endif()
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(QIGAO_COMPILER_OBFUSCATION_ENABLED OFF CACHE BOOL
      "Debug is not a protected source compilation" FORCE)
  return()
endif()
foreach(_field IN ITEMS
    QIGAO_OBFUSCATOR_PLUGIN_PATH
    QIGAO_OBFUSCATOR_PYTHON
    QIGAO_OBFUSCATOR_LAUNCHER)
  if(NOT DEFINED ENV{${_field}} OR "$ENV{${_field}}" STREQUAL "")
    message(FATAL_ERROR
      "obfuscator: true requires ${_field}, no unprotected fallback")
  endif()
endforeach()
# CMake compiler launchers apply to every C/C++ source compilation in
# this product graph. They do not affect binaries already compiled in
# external vcpkg packages. The actual compiler must load the pass plugin.
file(TO_CMAKE_PATH "$ENV{QIGAO_OBFUSCATOR_PYTHON}" _python)
file(TO_CMAKE_PATH "$ENV{QIGAO_OBFUSCATOR_LAUNCHER}" _script)
set(CMAKE_C_COMPILER_LAUNCHER "${_python};${_script}" CACHE STRING
    "Required Clang source obfuscator launcher" FORCE)
set(CMAKE_CXX_COMPILER_LAUNCHER "${_python};${_script}" CACHE STRING
    "Required Clang++ source obfuscator launcher" FORCE)
set(QIGAO_COMPILER_OBFUSCATION_ENABLED ON CACHE BOOL
    "Source obfuscation selected by compiler setup" FORCE)
unset(_python)
unset(_script)
unset(_field)
