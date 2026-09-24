vcpkg_check_linkage(ONLY_STATIC_LIBRARY)

vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL https://github.com/vnmakarov/mir.git
    REF 477d820e7b3054980ea1b936ecb2945c0e6465e8
)

file(MAKE_DIRECTORY "${SOURCE_PATH}/qigao-vcpkg")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/CMakeLists.txt"
     DESTINATION "${SOURCE_PATH}/qigao-vcpkg")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}/qigao-vcpkg"
    OPTIONS
        "-DMIR_SOURCE_DIR=${SOURCE_PATH}"
)

vcpkg_cmake_install()
vcpkg_copy_pdbs()

file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/debug/include")

vcpkg_cmake_config_fixup(
    PACKAGE_NAME MIR
    CONFIG_PATH "share/MIR"
)

file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage"
     DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")

vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
