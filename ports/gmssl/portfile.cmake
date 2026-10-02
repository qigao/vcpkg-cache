vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL "https://github.com/guanzhi/GmSSL.git"
    REF 7c9f02904ef33e59c87b4f16621cc8fd434e7579
)

# Upstream overrides CMAKE_INSTALL_PREFIX on MSVC. vcpkg owns the install root.
vcpkg_replace_string(
    "${SOURCE_PATH}/CMakeLists.txt"
    "set(CMAKE_INSTALL_PREFIX \"C:/Program Files/GmSSL\")"
    "# CMAKE_INSTALL_PREFIX is provided by vcpkg"
)

include("${CMAKE_CURRENT_LIST_DIR}/external-io.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/standard-tls.cmake")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()

if(NOT VCPKG_TARGET_IS_IOS)
    vcpkg_copy_tools(TOOL_NAMES gmssl AUTO_CLEAN)
endif()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/GmSSLConfig.cmake"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/gmssl")

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
