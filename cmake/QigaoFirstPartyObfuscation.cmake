# Qigao product-owned first-party protection policy.
#
# This file deliberately does not discover/probe a Clang version, plugin ABI,
# LLVM IR or the executable. The product owns its explicit target inventory;
# the normal compiler invocation applies -fpass-plugin to sensitive sources.
# Ordinary targets and imported third-party dependencies remain untouched.
#
# Include from the toolchain action's QIGAO_OBFUSCATION_POLICY_CMAKE path,
# after defining the product's native targets. Call exactly once per scope:
#
#   qigao_apply_obfuscation_policy(
#     SENSITIVE_TARGETS app_ai license_engine
#     ORDINARY_TARGETS app_frontend logging
#   )
#
# All first-party compiled targets in the scope belong in exactly one class.
# An imported library may NEVER claim sensitive source compilation.

include_guard(GLOBAL)
include(CMakeParseArguments)

function(qigao_apply_obfuscation_policy)
  cmake_parse_arguments(QIGAO "" "" "SENSITIVE_TARGETS;ORDINARY_TARGETS" ${ARGN})
  if(QIGAO_UNPARSED_ARGUMENTS OR QIGAO_KEYWORDS_MISSING_VALUES)
    message(FATAL_ERROR
      "qigao_apply_obfuscation_policy accepts only "
      "SENSITIVE_TARGETS and ORDINARY_TARGETS target lists")
  endif()

  set(_classified ${QIGAO_SENSITIVE_TARGETS} ${QIGAO_ORDINARY_TARGETS})
  if(NOT _classified)
    message(FATAL_ERROR
      "First-party policy must explicitly classify at least one compiled target")
  endif()

  get_property(_applied DIRECTORY PROPERTY QIGAO_OBFUSCATION_POLICY_APPLIED)
  if(_applied)
    message(FATAL_ERROR
      "First-party obfuscation policy already applied in this directory")
  endif()

  set(_seen "")
  foreach(_target IN LISTS _classified)
    if(_target IN_LIST _seen)
      message(FATAL_ERROR
        "First-party target '${_target}' classified twice or in both classes")
    endif()
    list(APPEND _seen "${_target}")
    if(NOT TARGET "${_target}")
      message(FATAL_ERROR
        "First-party target '${_target}' does not exist; no silent skip")
    endif()
    get_target_property(_alias "${_target}" ALIASED_TARGET)
    get_target_property(_imported "${_target}" IMPORTED)
    get_target_property(_type "${_target}" TYPE)
    if(_alias OR _imported)
      message(FATAL_ERROR
        "First-party target '${_target}' is imported/aliased, not a locally "
        "compiled source owner. A prebuilt static/DLL dependency is not protected.")
    endif()
    if(NOT _type MATCHES "^(STATIC_LIBRARY|SHARED_LIBRARY|MODULE_LIBRARY|OBJECT_LIBRARY|EXECUTABLE)$")
      message(FATAL_ERROR
        "First-party target '${_target}' has no compiled C/C++ source owner")
    endif()
  endforeach()

  set(_plugin "")
  if(DEFINED QIGAO_OBFUSCATOR_PLUGIN_PATH AND
     NOT "${QIGAO_OBFUSCATOR_PLUGIN_PATH}" STREQUAL "")
    set(_plugin "${QIGAO_OBFUSCATOR_PLUGIN_PATH}")
  elseif(DEFINED ENV{QIGAO_OBFUSCATOR_PLUGIN_PATH} AND
         NOT "$ENV{QIGAO_OBFUSCATOR_PLUGIN_PATH}" STREQUAL "")
    set(_plugin "$ENV{QIGAO_OBFUSCATOR_PLUGIN_PATH}")
  endif()

  if(QIGAO_SENSITIVE_TARGETS)
    # Only sanitize delimiters; do not probe compiler, plugin or runtime.
    if(_plugin MATCHES "[;\r\n]" OR _plugin MATCHES "\\$<")
      message(FATAL_ERROR "Invalid obfuscator plugin path delimiter")
    endif()
    if(_plugin STREQUAL "")
      # Single-config Release fails at configure. Multi-config Debug stays
      # buildable, but selecting Release feeds an intentionally nonexistent
      # pass plugin path to the actual compiler (no unprotected fallback).
      string(TOUPPER "${CMAKE_BUILD_TYPE}" _configuration)
      if(_configuration MATCHES "^(RELEASE|MINSIZEREL|RELWITHDEBINFO)$")
        message(FATAL_ERROR
          "Sensitive first-party source requires QIGAO_OBFUSCATOR_PLUGIN_PATH "
          "for protected Release; no fallback")
      endif()
      set(_plugin "${CMAKE_CURRENT_BINARY_DIR}/QIGAO_REQUIRED_OBFUSCATOR_PLUGIN_NOT_SET")
    endif()
    string(REPLACE "\\" "/" _plugin "${_plugin}")
  endif()

  foreach(_target IN LISTS QIGAO_ORDINARY_TARGETS)
    set_property(TARGET "${_target}" PROPERTY QIGAO_OBFUSCATION_CLASS "ordinary-first-party")
  endforeach()

  # PRIVATE compile options are intentional: third-party libraries and other
  # linked targets must not inherit the pass. Imported sensitive libs above
  # are rejected because link-time obfuscation cannot rewrite their code.
  set(_release "$<OR:$<CONFIG:Release>,$<CONFIG:MinSizeRel>,$<CONFIG:RelWithDebInfo>>")
  set(_source "$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>")
  foreach(_target IN LISTS QIGAO_SENSITIVE_TARGETS)
    target_compile_options("${_target}" PRIVATE
      "$<$<AND:${_release},${_source}>:-fpass-plugin=${_plugin}>")
    set_property(TARGET "${_target}" PROPERTY QIGAO_OBFUSCATION_CLASS "sensitive-first-party")
  endforeach()
  set_property(DIRECTORY PROPERTY QIGAO_OBFUSCATION_POLICY_APPLIED TRUE)
endfunction()
