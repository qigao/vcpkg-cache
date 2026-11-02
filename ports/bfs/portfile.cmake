# bfs configure runs target feature probes, so only native desktop builds are admitted.
set(VCPKG_BUILD_TYPE release)
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO tavianator/bfs
    REF "${VERSION}"
    SHA512 6f94c5f523b88e6689c82b0cd3ad7bb688c6cba02dc04f921e523fb175302b19ba3fd926a9389f26246afddff0f52dd0b44fc2cfbab0c608075551d99c4a88a6
)

# Upstream uses a make-based configure, not Autoconf. It accepts --prefix and
# --host, but not the helper's default Autoconf path/library switches.
set(platform_options)
if(VCPKG_TARGET_IS_OSX)
    # Leave room for vcpkg to rewrite Mach-O load commands after installation.
    list(APPEND platform_options "EXTRA_LDFLAGS=-Wl,-headerpad_max_install_names")
endif()
vcpkg_make_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    DISABLE_DEFAULT_OPTIONS
    LANGUAGES C
    OPTIONS
        ${platform_options}
        "--prefix=${CURRENT_INSTALLED_DIR}"
        "--version=${VERSION}"
        --enable-release
        --without-libacl
        --without-libcap
        --without-libselinux
        --without-liburing
        --without-oniguruma
)
vcpkg_make_install(TARGETS bfs install)
vcpkg_copy_tools(TOOL_NAMES bfs AUTO_CLEAN)
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE")
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)
