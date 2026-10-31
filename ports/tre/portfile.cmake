vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO laurikari/tre
    REF 71bfcaf0af3994384987c6c2679ed7d078ffe189
    SHA512 e92738843b9a5830990d83cda16bf925c1f93f2e9d8a72f690829cffd385eed607ec02132e06318608b1ca3f3532f344135838498e77e7dd86e33d0657a96a75
    PATCHES pointer-width-alignment.patch tre-start-position.patch
)

vcpkg_cmake_configure(
    SOURCE_PATH "${CMAKE_CURRENT_LIST_DIR}"
    OPTIONS "-DTRE_SOURCE_DIR=${SOURCE_PATH}"
)
vcpkg_cmake_install()
vcpkg_copy_pdbs()
vcpkg_cmake_config_fixup(
    PACKAGE_NAME unofficial-tre
    CONFIG_PATH share/unofficial-tre
)

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include"
                    "${CURRENT_PACKAGES_DIR}/debug/share")
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
