cmake_minimum_required(VERSION 3.23)
project(QigaoLemonHost LANGUAGES C)

if(LEMON_PACKAGE_LOCK)
  include("${CMAKE_CURRENT_LIST_DIR}/../../cmake/QigaoLemon.cmake")
  qigao_setup_lemon(LOCK_FILE "${LEMON_PACKAGE_LOCK}" HOST_RID "${LEMON_HOST_RID}"
    ARCHIVE_FILE "${LEMON_PACKAGE_ARCHIVE}")
  qigao_setup_lemon(LOCK_FILE "${LEMON_PACKAGE_LOCK}" HOST_RID "${LEMON_HOST_RID}"
    ARCHIVE_FILE "${LEMON_PACKAGE_ARCHIVE}")
else()
  if(NOT EXISTS "${LEMON_SOURCE_DIR}/lemon.c" OR NOT EXISTS "${LEMON_SOURCE_DIR}/lempar.c")
    message(FATAL_ERROR "Fetch the locked Lemon source pair before building")
  endif()
  add_executable(lemon "${LEMON_SOURCE_DIR}/lemon.c")
  target_compile_features(lemon PRIVATE c_std_11)
  add_executable(Lemon::Lemon ALIAS lemon)
  set(LEMPAR "${LEMON_SOURCE_DIR}/lempar.c")
endif()

# The tool's generated-parser test, not an installed SDK consumer project.
set(_generated "${CMAKE_CURRENT_BINARY_DIR}/generated")
add_custom_command(
  OUTPUT "${_generated}/host_smoke.c" "${_generated}/host_smoke.h"
  COMMAND "${CMAKE_COMMAND}" -E make_directory "${_generated}"
  COMMAND "$<TARGET_FILE:Lemon::Lemon>" -q "-T${LEMPAR}"
    "-d${_generated}" "${CMAKE_CURRENT_LIST_DIR}/host_smoke.y"
  DEPENDS Lemon::Lemon "${LEMPAR}" "${CMAKE_CURRENT_LIST_DIR}/host_smoke.y"
  VERBATIM)
add_executable(lemon_host_smoke host_smoke.c "${_generated}/host_smoke.c")
target_compile_features(lemon_host_smoke PRIVATE c_std_11)
target_include_directories(lemon_host_smoke PRIVATE "${_generated}" "${CMAKE_CURRENT_LIST_DIR}")
enable_testing()
add_test(NAME lemon.generated_parser COMMAND lemon_host_smoke)
