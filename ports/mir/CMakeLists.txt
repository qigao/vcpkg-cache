cmake_minimum_required(VERSION 3.20)
project(MIR VERSION 1.0.0 LANGUAGES C)

include(GNUInstallDirs)

if(NOT DEFINED MIR_SOURCE_DIR)
  message(FATAL_ERROR "MIR_SOURCE_DIR is required")
endif()

find_package(Threads REQUIRED)

add_library(mir STATIC
  "${MIR_SOURCE_DIR}/mir.c"
  "${MIR_SOURCE_DIR}/mir-gen.c")

add_library(MIR::MIR ALIAS mir)

set_target_properties(mir PROPERTIES
  EXPORT_NAME MIR
  POSITION_INDEPENDENT_CODE ON)

target_compile_features(mir PUBLIC c_std_11)

target_include_directories(mir
  PUBLIC
    $<BUILD_INTERFACE:${MIR_SOURCE_DIR}>
    $<INSTALL_INTERFACE:${CMAKE_INSTALL_INCLUDEDIR}>)

target_compile_definitions(mir PUBLIC MIR_PARALLEL_GEN)

target_link_libraries(mir PUBLIC Threads::Threads)

if(CMAKE_DL_LIBS)
  target_link_libraries(mir PUBLIC ${CMAKE_DL_LIBS})
endif()

if(UNIX AND NOT APPLE)
  target_link_libraries(mir PUBLIC m)
endif()

install(
  TARGETS mir
  EXPORT MIRTargets
  ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR})

install(
  FILES
    "${MIR_SOURCE_DIR}/mir.h"
    "${MIR_SOURCE_DIR}/mir-gen.h"
    "${MIR_SOURCE_DIR}/mir-dlist.h"
    "${MIR_SOURCE_DIR}/mir-varr.h"
    "${MIR_SOURCE_DIR}/mir-htab.h"
  DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

install(
  EXPORT MIRTargets
  FILE MIRTargets.cmake
  NAMESPACE MIR::
  DESTINATION share/MIR)

file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/MIRConfig.cmake"
"include(CMakeFindDependencyMacro)\nfind_dependency(Threads)\ninclude(\"\${CMAKE_CURRENT_LIST_DIR}/MIRTargets.cmake\")\n")

install(
  FILES "${CMAKE_CURRENT_BINARY_DIR}/MIRConfig.cmake"
  DESTINATION share/MIR)
