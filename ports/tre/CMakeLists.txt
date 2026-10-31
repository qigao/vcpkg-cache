cmake_minimum_required(VERSION 3.20)
project(TRE VERSION 0.9.0 LANGUAGES C)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

if(NOT DEFINED TRE_SOURCE_DIR OR NOT IS_DIRECTORY "${TRE_SOURCE_DIR}")
  message(FATAL_ERROR "TRE_SOURCE_DIR must name the extracted TRE source directory")
endif()

set(TRE_VERSION "${PROJECT_VERSION}")
set(TRE_VERSION_1 "${PROJECT_VERSION_MAJOR}")
set(TRE_VERSION_2 "${PROJECT_VERSION_MINOR}")
set(TRE_VERSION_3 "${PROJECT_VERSION_PATCH}")
configure_file(config.h.in config.h @ONLY)
configure_file(tre-config.h.in include/tre/tre-config.h @ONLY)

add_library(tre STATIC
  "${TRE_SOURCE_DIR}/lib/tre-ast.c"
  "${TRE_SOURCE_DIR}/lib/tre-compile.c"
  "${TRE_SOURCE_DIR}/lib/tre-match-backtrack.c"
  "${TRE_SOURCE_DIR}/lib/tre-match-parallel.c"
  "${TRE_SOURCE_DIR}/lib/tre-match-approx.c"
  "${TRE_SOURCE_DIR}/lib/tre-mem.c"
  "${TRE_SOURCE_DIR}/lib/tre-parse.c"
  "${TRE_SOURCE_DIR}/lib/tre-stack.c"
  "${TRE_SOURCE_DIR}/lib/regcomp.c"
  "${TRE_SOURCE_DIR}/lib/regexec.c"
  "${TRE_SOURCE_DIR}/lib/regerror.c")
add_library(unofficial::tre::tre ALIAS tre)
set_target_properties(tre PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_compile_definitions(tre PRIVATE HAVE_CONFIG_H)
if(MSVC)
  target_compile_definitions(tre PRIVATE _CRT_SECURE_NO_WARNINGS
                                         _CRT_SECURE_NO_DEPRECATE)
endif()
target_include_directories(tre
  PUBLIC
    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include>
    $<BUILD_INTERFACE:${CMAKE_CURRENT_BINARY_DIR}/include/tre>
    $<BUILD_INTERFACE:${TRE_SOURCE_DIR}/include>
    $<INSTALL_INTERFACE:include>
  PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${TRE_SOURCE_DIR}/lib")

install(TARGETS tre EXPORT unofficial-tre-targets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})
install(FILES
  "${TRE_SOURCE_DIR}/include/tre/tre.h"
  "${TRE_SOURCE_DIR}/include/tre/regex.h"
  "${CMAKE_CURRENT_BINARY_DIR}/include/tre/tre-config.h"
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/tre)
install(EXPORT unofficial-tre-targets
  FILE unofficial-tre-targets.cmake
  NAMESPACE unofficial::tre::
  DESTINATION share/unofficial-tre)
configure_package_config_file(unofficial-tre-config.cmake.in
  "${CMAKE_CURRENT_BINARY_DIR}/unofficial-tre-config.cmake"
  INSTALL_DESTINATION share/unofficial-tre)
write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/unofficial-tre-config-version.cmake"
  VERSION "${PROJECT_VERSION}"
  COMPATIBILITY SameMajorVersion)
install(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/unofficial-tre-config.cmake"
  "${CMAKE_CURRENT_BINARY_DIR}/unofficial-tre-config-version.cmake"
  DESTINATION share/unofficial-tre)
