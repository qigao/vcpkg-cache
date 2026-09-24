vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO vnmakarov/mir
    REF a8ab7c31cd5f9b23b77d84c60b3d83e62d9d304c
    SHA512 5758942c2aeb22317005ed1bfbd104387674e74001ceb0da77485ed8ba011ae2b39e7a2acf8d9425e77741adb233966fc25c4cafca7f25efcceb96e161500039
    HEAD_REF master
    PATCHES
        install-export.patch
)

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DBUILD_TESTING=OFF
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/MIRConfig.cmake"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/mir")
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/MIRConfig.cmake"
     DESTINATION "${CURRENT_PACKAGES_DIR}/debug/share/mir")

vcpkg_cmake_config_fixup(
    PACKAGE_NAME MIR
    CONFIG_PATH "share/mir"
)

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
)

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
