# Command-line tools only; there is no public ugrep C/C++ library export.
set(VCPKG_BUILD_TYPE release)
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO Genivia/ugrep
    REF f2cc252c011460f6c75b1fb591813b4b6b59c225 # v7.8.5
    SHA512 13a4930698e3366168294ac07d156971d1540a2925a1b2ea77e52b0ece79e8eebdc84d31ce088ebb13e38ed07be35470becbd57c74d324e1f4de9dcb28094050
    PATCHES require-pcre2.patch
)

if(VCPKG_TARGET_IS_WINDOWS)
    vcpkg_cmake_configure(
        SOURCE_PATH "${CMAKE_CURRENT_LIST_DIR}"
        OPTIONS "-DUGREP_SOURCE_DIR=${SOURCE_PATH}"
    )
    vcpkg_cmake_install()
    vcpkg_copy_pdbs()
else()
    # Use the generated upstream configure script. Disable optional dependencies
    # explicitly so installed system libraries cannot change the cached feature set.
    vcpkg_make_configure(
        SOURCE_PATH "${SOURCE_PATH}"
        # Upstream install-exec-hook reads bin/ugrep+ and bin/ug+ relative
        # to the build directory. Its out-of-tree install loses these files.
        COPY_SOURCE
        DISABLE_DEFAULT_OPTIONS
        OPTIONS
            "--prefix=${CURRENT_INSTALLED_DIR}"
            "--mandir=${CURRENT_INSTALLED_DIR}/share/ugrep"
            "--with-pcre2=${CURRENT_INSTALLED_DIR}"
            --disable-static
            --without-zlib
            --without-boost-regex
            --disable-avx2
            --disable-avx512
            --without-bash-completion-dir
            --without-fish-completion-dir
            --without-zsh-completion-dir
    )
    vcpkg_make_install()
    # The native cache excludes symlinks. Materialize upstream's one internal
    # manual alias as the same regular file; keep the archive admission strict.
    set(_ugrep_man "${CURRENT_PACKAGES_DIR}/share/ugrep/man1")
    file(READ_SYMLINK "${_ugrep_man}/ug.1" _ugrep_alias)
    if(NOT _ugrep_alias STREQUAL "ugrep.1")
        message(FATAL_ERROR "Unexpected upstream ugrep manual alias: ${_ugrep_alias}")
    endif()
    file(REMOVE "${_ugrep_man}/ug.1")
    configure_file("${_ugrep_man}/ugrep.1" "${_ugrep_man}/ug.1" COPYONLY)
endif()

vcpkg_copy_tools(TOOL_NAMES ugrep ugrep-indexer AUTO_CLEAN)
# The upstream 'ug' alias and shell wrappers are not packaged by this port.
file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin" "${CURRENT_PACKAGES_DIR}/debug")
file(INSTALL "${CMAKE_CURRENT_LIST_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/LICENSE.txt")
set(VCPKG_POLICY_EMPTY_INCLUDE_FOLDER enabled)
