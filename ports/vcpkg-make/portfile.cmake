# Import the exact upstream helper port; the only adaptation selects the
# native Windows pkg-config already provided by setup-vcpkg-cache.
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO microsoft/vcpkg
    REF 04a9d8e5212d01ee1dd9478eadd9caade4f8b0d4
    SHA512 96f02b59f563251659a677623673d2af8b0887573c1aad3ba39e9d3d9d38e334374ad3edcf62eca9413564960d6e6103cce79eee63767b488ff56c3ac471ab3b
    PATCHES native-windows-pkgconfig.patch
)

set(VCPKG_POLICY_CMAKE_HELPER_PORT enabled)

set(automake_version 1.17)
vcpkg_download_distfile(ARCHIVE
    URLS "https://ftpmirror.gnu.org/gnu/automake/automake-${automake_version}.tar.gz"
         "https://ftp.gnu.org/gnu/automake/automake-${automake_version}.tar.gz"
         "https://www.mirrorservice.org/sites/ftp.gnu.org/gnu/automake/automake-${automake_version}.tar.gz"
    FILENAME "automake-${automake_version}.tar.gz"
    SHA512 11357dfab8cbf4b5d94d9d06e475732ca01df82bef1284888a34bd558afc37b1a239bed1b5eb18a9dbcc326344fb7b1b301f77bb8385131eb8e1e118b677883a
)

vcpkg_extract_source_archive(
    automake_source
    ARCHIVE "${ARCHIVE}"
)

file(COPY
        "${SOURCE_PATH}/ports/vcpkg-make/configure.ac"
        "${SOURCE_PATH}/ports/vcpkg-make/vcpkg_make_common.cmake"
        "${SOURCE_PATH}/ports/vcpkg-make/vcpkg_make_configure.cmake"
        "${SOURCE_PATH}/ports/vcpkg-make/vcpkg_make_install.cmake"
        "${SOURCE_PATH}/ports/vcpkg-make/vcpkg_make.cmake"
        "${SOURCE_PATH}/ports/vcpkg-make/vcpkg_scripts.cmake"
        "${SOURCE_PATH}/ports/vcpkg-make/vcpkg-port-config.cmake"
    DESTINATION
        "${CURRENT_PACKAGES_DIR}/share/${PORT}"
)

file(COPY
        "${automake_source}/lib/ar-lib"
        "${automake_source}/lib/compile"
        "${SOURCE_PATH}/ports/vcpkg-make/wrappers/"
    DESTINATION
        "${CURRENT_PACKAGES_DIR}/share/${PORT}/wrappers"
)

vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")
include("${SOURCE_PATH}/ports/vcpkg-make/vcpkg_scripts.cmake")
include("${SOURCE_PATH}/ports/vcpkg-make/vcpkg_make.cmake")
cmake_path(GET VCPKG_DETECTED_CMAKE_C_COMPILER FILENAME compiler_name)
z_vcpkg_make_determine_target_triplet(build_opt_triplet COMPILER_NAME "${compiler_name}")
set(build_opt_source "vcpkg")
if(NOT build_opt_triplet)
    set(ENV{CC_FOR_BUILD} "${VCPKG_DETECTED_CMAKE_C_COMPILER}")
    vcpkg_execute_required_process(
        COMMAND "sh" -c "${automake_source}/lib/config.guess"
        OUTPUT_VARIABLE build_opt_triplet
        OUTPUT_STRIP_TRAILING_WHITESPACE
        WORKING_DIRECTORY "${CURRENT_BUILDTREES_DIR}"
        LOGNAME "config-guess-${TARGET_TRIPLET}"
    )
    if(NOT build_opt_triplet)
        message("${Z_VCPKG_BACKCOMPAT_MESSAGE_LEVEL}"
            "Unknown autotools triplet for vcpkg ${TARGET_TRIPLET} triplet. "
            "You may need to define VCPKG_MAKE_BUILD_TRIPLET in the triplet file."
        )
    endif()
    set(build_opt_source "config.guess")
endif()
file(WRITE "${CURRENT_PACKAGES_DIR}/share/${PORT}/build_opt_triplet.txt" "${build_opt_triplet}\n")
message(STATUS "${TARGET_TRIPLET} autotools triplet: ${build_opt_triplet} (from ${build_opt_source})")

vcpkg_install_copyright(
    COMMENT [[
The cmake scripts are under vcpkg's MIT license terms, see LICENSE.txt below.
The port also installs shell scripts from GNU Automake.
These scripts are under GPL-2.0-or-later, see COPYING below.
]]
    FILE_LIST
        "${VCPKG_ROOT_DIR}/LICENSE.txt"
        "${automake_source}/COPYING"
)
