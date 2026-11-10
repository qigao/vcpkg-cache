# Shared native SDK/tool restore. All network I/O stays in the curl-only CLI.
# Include from a product CMakeLists, or run directly with cmake -P (see docs).
include_guard(GLOBAL)

function(_qigao_native_run out_json)
  find_package(Python3 3.12 REQUIRED COMPONENTS Interpreter)
  execute_process(
    COMMAND "${Python3_EXECUTABLE}"
      "${CMAKE_CURRENT_FUNCTION_LIST_DIR}/../scripts/restore-native-dependency.py" ${ARGN}
    RESULT_VARIABLE _status OUTPUT_VARIABLE _json ERROR_VARIABLE _diagnostics
    OUTPUT_STRIP_TRAILING_WHITESPACE)
  if(NOT "${_status}" STREQUAL "0")
    message(FATAL_ERROR "Native dependency command failed (${_status}):\n${_diagnostics}")
  endif()
  set("${out_json}" "${_json}" PARENT_SCOPE)
endfunction()

function(qigao_resolve_native_release)
  cmake_parse_arguments(PARSE_ARGV 0 DEP "" "DESCRIPTOR;LOCK_FILE" "")
  if(DEP_UNPARSED_ARGUMENTS OR NOT DEP_DESCRIPTOR OR NOT DEP_LOCK_FILE)
    message(FATAL_ERROR "qigao_resolve_native_release requires DESCRIPTOR and generated LOCK_FILE")
  endif()
  get_filename_component(_descriptor "${DEP_DESCRIPTOR}" ABSOLUTE)
  get_filename_component(_lock "${DEP_LOCK_FILE}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")
  _qigao_native_run(_result resolve-release "${_descriptor}" --output-lock "${_lock}")
endfunction()

# Explicit lock update; call from an update script, not on every configure.
function(qigao_resolve_native_package)
  cmake_parse_arguments(PARSE_ARGV 0 DEP "" "PACKAGE_ID;VERSION;LOCK_FILE" "")
  if(DEP_UNPARSED_ARGUMENTS OR NOT DEP_PACKAGE_ID OR NOT DEP_VERSION OR NOT DEP_LOCK_FILE)
    message(FATAL_ERROR "qigao_resolve_native_package requires PACKAGE_ID, VERSION (exact or latest), LOCK_FILE")
  endif()
  get_filename_component(_lock "${DEP_LOCK_FILE}" ABSOLUTE)
  _qigao_native_run(_result resolve "${DEP_PACKAGE_ID}" --version "${DEP_VERSION}" --output-lock "${_lock}")
  message(STATUS "Updated native dependency lock: ${_lock}")
endfunction()

function(qigao_restore_native_dependency)
  cmake_parse_arguments(PARSE_ARGV 0 DEP ""
    "LOCK_FILE;DESTINATION;PAYLOAD;ARCHIVE_FILE;OUT_ROOT;OUT_RECEIPT" "REQUIRED_FILES;EXECUTABLES")
  if(DEP_UNPARSED_ARGUMENTS OR NOT DEP_LOCK_FILE)
    message(FATAL_ERROR "qigao_restore_native_dependency requires LOCK_FILE")
  endif()
  if(NOT DEP_PAYLOAD)
    set(DEP_PAYLOAD ".")
  endif()
  get_filename_component(_lock "${DEP_LOCK_FILE}" ABSOLUTE)
  if(NOT EXISTS "${_lock}")
    message(FATAL_ERROR "Native dependency lock is missing: ${_lock}; resolve it explicitly first")
  endif()
  if(NOT DEP_DESTINATION)
    # A changed lock or selection gets another directory; configure never
    # deletes or replaces a previous installation to perform an upgrade.
    file(READ "${_lock}" _lock_text)
    string(SHA256 _key "${_lock_text}|${DEP_PAYLOAD}|${DEP_REQUIRED_FILES}|${DEP_EXECUTABLES}")
    set(DEP_DESTINATION "${CMAKE_BINARY_DIR}/_deps/qigao-native/${_key}")
  endif()
  get_filename_component(_destination "${DEP_DESTINATION}" ABSOLUTE BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")
  set(_arguments locked "${_lock}" --destination "${_destination}" --payload "${DEP_PAYLOAD}" --reuse)
  if(DEP_ARCHIVE_FILE)
    get_filename_component(_archive "${DEP_ARCHIVE_FILE}" ABSOLUTE)
    list(APPEND _arguments --archive "${_archive}")
  endif()
  foreach(_file IN LISTS DEP_REQUIRED_FILES)
    list(APPEND _arguments --require "${_file}")
  endforeach()
  foreach(_file IN LISTS DEP_EXECUTABLES)
    list(APPEND _arguments --executable "${_file}")
  endforeach()
  _qigao_native_run(_result ${_arguments})
  string(JSON _root GET "${_result}" root)
  string(JSON _receipt GET "${_result}" receipt)
  if(DEP_OUT_ROOT)
    set("${DEP_OUT_ROOT}" "${_root}" PARENT_SCOPE)
  endif()
  if(DEP_OUT_RECEIPT)
    set("${DEP_OUT_RECEIPT}" "${_receipt}" PARENT_SCOPE)
  endif()
endfunction()

# This is the actual restore operation in script mode, with no test project,
# compiler detection, target creation or product dependency graph.
if(CMAKE_SCRIPT_MODE_FILE STREQUAL CMAKE_CURRENT_LIST_FILE)
  if(QIGAO_PACKAGE_ID)
    qigao_resolve_native_package(PACKAGE_ID "${QIGAO_PACKAGE_ID}"
      VERSION "${QIGAO_VERSION}" LOCK_FILE "${QIGAO_LOCK_FILE}")
  else()
    qigao_restore_native_dependency(
      LOCK_FILE "${QIGAO_LOCK_FILE}" DESTINATION "${QIGAO_DESTINATION}"
      PAYLOAD "${QIGAO_PAYLOAD}" REQUIRED_FILES ${QIGAO_REQUIRED_FILES}
      EXECUTABLES ${QIGAO_EXECUTABLES} OUT_ROOT _root OUT_RECEIPT _receipt)
    message(STATUS "QIGAO_DEPENDENCY_ROOT=${_root}")
    message(STATUS "QIGAO_DEPENDENCY_RECEIPT=${_receipt}")
  endif()
endif()
