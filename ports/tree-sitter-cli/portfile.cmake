set(VCPKG_POLICY_EMPTY_PACKAGE enabled)

set(key NOTFOUND)
if(VCPKG_TARGET_IS_WINDOWS)
    set(key "Windows-${VCPKG_TARGET_ARCHITECTURE}")
elseif(VCPKG_CMAKE_SYSTEM_NAME)
    set(key "${VCPKG_CMAKE_SYSTEM_NAME}-${VCPKG_TARGET_ARCHITECTURE}")
endif()

# The producer prefetch and this port consume the same immutable source catalog.
file(READ "${CMAKE_CURRENT_LIST_DIR}/sources.json" sources)
string(JSON source_version GET "${sources}" version)
if(NOT source_version STREQUAL VERSION)
    message(FATAL_ERROR "Tree-sitter CLI source catalog differs from the selected version")
endif()
foreach(field IN ITEMS url filename sha512)
    string(JSON license_${field} GET "${sources}" license ${field})
endforeach()
vcpkg_download_distfile(license
    URLS "${license_url}" FILENAME "${license_filename}" SHA512 "${license_sha512}")

set(keys "${key}")
if(VCPKG_TREE_SITTER_UPDATE)
    string(JSON count LENGTH "${sources}" binaries)
    math(EXPR last "${count} - 1")
    set(keys)
    foreach(index RANGE 0 ${last})
        string(JSON entry MEMBER "${sources}" binaries ${index})
        list(APPEND keys "${entry}")
    endforeach()
endif()
foreach(entry IN LISTS keys)
    string(JSON selected ERROR_VARIABLE error GET "${sources}" binaries "${entry}")
    if(error)
        message(FATAL_ERROR "Unsupported platform '${entry}'")
    endif()
    foreach(field IN ITEMS url filename sha512)
        string(JSON asset_${field} GET "${selected}" ${field})
    endforeach()
    vcpkg_download_distfile(archive_path
        URLS "${asset_url}" FILENAME "${asset_filename}" SHA512 "${asset_sha512}")
endforeach()
if(VCPKG_TREE_SITTER_UPDATE)
    message(STATUS "All downloads are up-to-date.")
    message(FATAL_ERROR "Stopping due to VCPKG_TREE_SITTER_UPDATE being enabled.")
endif()

vcpkg_find_acquire_program(PYTHON3)
vcpkg_execute_required_process(
    ALLOW_IN_DOWNLOAD_MODE
    COMMAND "${PYTHON3}" "${CMAKE_CURRENT_LIST_DIR}/unpack.py" "${archive_path}"
        "${CURRENT_PACKAGES_DIR}/tools/${PORT}/tree-sitter${VCPKG_HOST_EXECUTABLE_SUFFIX}"
    WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
    LOGNAME "unpack-${TARGET_TRIPLET}"
)

file(CHMOD "${CURRENT_PACKAGES_DIR}/tools/${PORT}/tree-sitter${VCPKG_HOST_EXECUTABLE_SUFFIX}"
    FILE_PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE
)

vcpkg_install_copyright(FILE_LIST "${license}"
	COMMENT [[
Tree-sitter is licensed under the MIT license. The tree-sitter CLI uses
third-party components which are not listed individually here.
]])
