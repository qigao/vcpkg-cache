vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

if(VCPKG_TARGET_IS_WINDOWS)
    message(FATAL_ERROR "mir-jit is not qualified for Windows in qigao/vcpkg-cache")
endif()

vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL "https://github.com/vnmakarov/mir.git"
    REF 477d820e7b3054980ea1b936ecb2945c0e6465e8
    FETCH_REF v1.0.0
)

vcpkg_cmake_configure(
    SOURCE_PATH "${CMAKE_CURRENT_LIST_DIR}"
    OPTIONS
        "-DMIR_SOURCE_DIR=${SOURCE_PATH}"
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share")

vcpkg_cmake_config_fixup(
    PACKAGE_NAME MIR
    CONFIG_PATH "lib/cmake/MIR")

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
