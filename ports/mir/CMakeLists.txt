cmake_minimum_required(VERSION 3.20)

project(MIRPackage LANGUAGES C)

include(GNUInstallDirs)
include(CMakePackageConfigHelpers)

if(NOT DEFINED MIR_SOURCE_DIR)
  message(FATAL_ERROR "MIR_SOURCE_DIR is required")
endif()

find_package(Threads REQUIRED)

add_library(mir_jit STATIC
  "${MIR_SOURCE_DIR}/mir.c"
  "${MIR_SOURCE_DIR}/mir-gen.c")

add_library(MIR::MIR ALIAS mir_jit)

set_target_properties(mir_jit PROPERTIES
  EXPORT_NAME MIR
  POSITION_INDEPENDENT_CODE ON)

target_compile_features(mir_jit PUBLIC c_std_11)

target_include_directories(mir_jit
  PUBLIC
    $<BUILD_INTERFACE:${MIR_SOURCE_DIR}>
    $<INSTALL_INTERFACE:include>)

target_link_libraries(mir_jit
  PUBLIC Threads::Threads
  PRIVATE ${CMAKE_DL_LIBS})

if(NOT WIN32)
  target_compile_options(mir_jit PRIVATE
    -fsigned-char)
endif()

if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
  include(CheckCCompilerFlag)
  check_c_compiler_flag("-fno-tree-sra" MIR_HAS_NO_TREE_SRA)
  if(MIR_HAS_NO_TREE_SRA)
    target_compile_options(mir_jit PRIVATE -fno-tree-sra)
  endif()
  check_c_compiler_flag("-fno-ipa-cp-clone" MIR_HAS_NO_IPA_CP_CLONE)
  if(MIR_HAS_NO_IPA_CP_CLONE)
    target_compile_options(mir_jit PRIVATE -fno-ipa-cp-clone)
  endif()
endif()

install(TARGETS mir_jit
  EXPORT MIRTargets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
  LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
  RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR})

file(GLOB MIR_PUBLIC_HEADERS
  "${MIR_SOURCE_DIR}/mir*.h")

install(FILES ${MIR_PUBLIC_HEADERS}
  DESTINATION include)

configure_package_config_file(
  "${CMAKE_CURRENT_LIST_DIR}/MIRConfig.cmake.in"
  "${CMAKE_CURRENT_BINARY_DIR}/MIRConfig.cmake"
  INSTALL_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/MIR")

write_basic_package_version_file(
  "${CMAKE_CURRENT_BINARY_DIR}/MIRConfigVersion.cmake"
  VERSION 1.0.0
  COMPATIBILITY SameMajorVersion)

install(FILES
  "${CMAKE_CURRENT_BINARY_DIR}/MIRConfig.cmake"
  "${CMAKE_CURRENT_BINARY_DIR}/MIRConfigVersion.cmake"
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/MIR")

install(EXPORT MIRTargets
  FILE MIRTargets.cmake
  NAMESPACE MIR::
  DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/MIR")
