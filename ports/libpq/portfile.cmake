include("${CMAKE_CURRENT_LIST_DIR}/tls-provider.cmake")

if("ssl" IN_LIST FEATURES)
    set(LIBPQ_WITH_SSL ON)
else()
    set(LIBPQ_WITH_SSL OFF)
endif()

vcpkg_download_distfile(ARCHIVE
    URLS "https://ftp.postgresql.org/pub/source/v${VERSION}/postgresql-${VERSION}.tar.bz2"
         "https://www.mirrorservice.org/sites/ftp.postgresql.org/source/v${VERSION}/postgresql-${VERSION}.tar.bz2"
    FILENAME "postgresql-${VERSION}.tar.bz2"
    SHA512 23a3d983c5be49c3daabbbde35db2920bd2e2ba8d9baba805e7908da1f43153ff438c76c253ea8ee8ac6f8a9313fbf0348a1e9b45ef530c5e156fee0daceb814
)

vcpkg_extract_source_archive(
    SOURCE_PATH
    ARCHIVE "${ARCHIVE}"
    PATCHES
        unix/installdirs.patch
        unix/fix-configure.patch
        unix/single-linkage.patch
        unix/no-server-tools.patch
        unix/mingw-install.patch
        unix/python.patch
        windows/macro-def.patch
        windows/win_bison_flex.patch
        windows/msbuild.patch
        ${LIBPQ_TLS_WINDOWS_PATCHES}
        windows/spin_delay.patch
        windows/tcl-9.0-alpha.patch
        android/unversioned_so.patch
)

include("${CMAKE_CURRENT_LIST_DIR}/external-channel-binding.cmake")

file(GLOB _py3_include_path "${CURRENT_HOST_INSTALLED_DIR}/include/python3*")
string(REGEX MATCH "python3\\.([0-9]+)" _python_version_tmp "${_py3_include_path}")
set(PYTHON_VERSION_MINOR "${CMAKE_MATCH_1}")

if("client" IN_LIST FEATURES)
    set(HAS_TOOLS TRUE)
else()
    set(HAS_TOOLS FALSE)
endif()

# PostgreSQL's configure.ac demands a runnable host zic when
# "cross_compiling=yes". The pinned libpq-only Makefile builds only
# src/{include,common,port,interfaces/libpq,ecpg} and pg_config;
# it does not build/install src/timezone or any timezone database.
# Keep the mandatory zic check for the full client-tools profile.
# Never inject a dummy zic or a fabricated --with-system-tzdata path.
if(NOT HAS_TOOLS)
    set(_libpq_configure_ac "${SOURCE_PATH}/configure.ac")
    file(READ "${_libpq_configure_ac}" _libpq_configure_text)
    set(_libpq_zic_anchor
        "if test x\"$cross_compiling\" = x\"yes\" && test -z \"$with_system_tzdata\"; then")
    string(FIND "${_libpq_configure_text}" "${_libpq_zic_anchor}" _libpq_zic_position)
    if(_libpq_zic_position EQUAL -1)
        message(FATAL_ERROR "Pinned PostgreSQL 16.9 zic configure anchor changed")
    endif()
    vcpkg_replace_string("${_libpq_configure_ac}"
        "${_libpq_zic_anchor}"
        "if test x\"$cross_compiling\" = x\"yes\" && test -z \"$with_system_tzdata\" && test x\"$LIBPQ_ENABLE_TOOLS\" = x\"yes\"; then")
endif()

vcpkg_cmake_get_vars(cmake_vars_file)
include("${cmake_vars_file}")

# Clang's __builtin_setjmp/longjmp require a pointer buffer (void **),
# but PostgreSQL 16.9's MinGW fallback defines sigjmp_buf as
# intptr_t[5]. GCC accepts the original, while llvm-mingw Clang 23
# rejects it as incompatible pointer types. A pointer[5] has the same
# size/alignment as intptr_t[5] on the selected Win64 ABI, preserving
# the five-slot builtin storage and paired longjmp behavior.
if(VCPKG_TARGET_IS_MINGW AND
   VCPKG_DETECTED_CMAKE_C_COMPILER MATCHES "clang(\\.exe)?$")
    set(_libpq_jump_header "${SOURCE_PATH}/src/include/c.h")
    file(READ "${_libpq_jump_header}" _libpq_jump_source)
    string(FIND "${_libpq_jump_source}" "typedef intptr_t sigjmp_buf[5];" _libpq_jump_pos)
    if(_libpq_jump_pos EQUAL -1)
        message(FATAL_ERROR "Pinned PostgreSQL MinGW sigjmp_buf declaration changed")
    endif()
    vcpkg_replace_string("${_libpq_jump_header}"
        "typedef intptr_t sigjmp_buf[5];"
        "typedef void *sigjmp_buf[5];")

    # PostgreSQL 16.9 forces its own getopt_long() semantics on Windows.
    # Clang/llvm-mingw exposes struct option from the native getopt.h,
    # while the pinned generated pg_config.h may report HAVE_STRUCT_OPTION
    # without making the definition visible to getopt_long.c. Keep the
    # original PostgreSQL parser and include the actual type definition.
    set(_libpq_getopt_header "${SOURCE_PATH}/src/include/getopt_long.h")
    file(READ "${_libpq_getopt_header}" _libpq_getopt_text)
    string(FIND "${_libpq_getopt_text}" "#include \"pg_getopt.h\"" _libpq_getopt_pos)
    if(_libpq_getopt_pos EQUAL -1)
        message(FATAL_ERROR "Pinned PostgreSQL getopt_long include anchor changed")
    endif()
    vcpkg_replace_string("${_libpq_getopt_header}"
        "#include \"pg_getopt.h\""
        "#include \"pg_getopt.h\"\n#if defined(__clang__) && defined(__MINGW64__)\n#include <getopt.h>\n#endif")

    # The toolchain's native winpthread already declares pthread_barrier_t
    # and the barrier API in pthread.h. Make the real linker admission
    # resolve -lwinpthread before PostgreSQL decides whether to compile
    # its conflicting fallback implementation. No hardcoded ac_cv=pass.
    set(ENV{LIBS} "$ENV{LIBS} -lwinpthread")
endif()

set(required_programs BISON FLEX)
if(VCPKG_DETECTED_MSVC OR NOT VCPKG_HOST_IS_WINDOWS)
    list(APPEND required_programs PERL)
endif()
foreach(program_name IN LISTS required_programs)
    vcpkg_find_acquire_program(${program_name})
    get_filename_component(program_dir ${${program_name}} DIRECTORY)
    vcpkg_add_to_path(PREPEND "${program_dir}")
endforeach()

if(VCPKG_DETECTED_MSVC)
    if("xml" IN_LIST FEATURES)
        x_vcpkg_pkgconfig_get_modules(
            PREFIX PC_LIBXML2
            MODULES --msvc-syntax libxml-2.0
            LIBS
        )
        separate_arguments(LIBXML2_LIBS_DEBUG NATIVE_COMMAND "${PC_LIBXML2_LIBS_DEBUG}")
        separate_arguments(LIBXML2_LIBS_RELEASE NATIVE_COMMAND "${PC_LIBXML2_LIBS_RELEASE}")
    endif()
    if("xslt" IN_LIST FEATURES)
        x_vcpkg_pkgconfig_get_modules(
            PREFIX PC_LIBXSLT
            MODULES --msvc-syntax libxslt
            LIBS
        )
        separate_arguments(LIBXSLT_LIBS_DEBUG NATIVE_COMMAND "${PC_LIBXSLT_LIBS_DEBUG}")
        separate_arguments(LIBXSLT_LIBS_RELEASE NATIVE_COMMAND "${PC_LIBXSLT_LIBS_RELEASE}")
    endif()

    include("${CMAKE_CURRENT_LIST_DIR}/build-msvc.cmake")
    if(NOT VCPKG_BUILD_TYPE)
        build_msvc(DEBUG "${SOURCE_PATH}")
    endif()
    build_msvc(RELEASE "${SOURCE_PATH}")

    if(VCPKG_LIBRARY_LINKAGE STREQUAL "static")
        file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/bin" "${CURRENT_PACKAGES_DIR}/debug/bin")
    endif()

    if(HAS_TOOLS)
        vcpkg_copy_tool_dependencies("${CURRENT_PACKAGES_DIR}/tools/${PORT}")
    else()
        file(REMOVE_RECURSE "${CURRENT_PACKAGES_DIR}/tools")
    endif()
else()
    file(COPY "${CMAKE_CURRENT_LIST_DIR}/Makefile" DESTINATION "${SOURCE_PATH}")

    vcpkg_list(SET BUILD_OPTS)
    foreach(option IN ITEMS icu lz4 nls readline xml xslt zlib zstd)
        if(option IN_LIST FEATURES)
            list(APPEND BUILD_OPTS --with-${option})
        else()
            list(APPEND BUILD_OPTS --without-${option})
        endif()
    endforeach()
    if(LIBPQ_WITH_SSL)
        list(APPEND BUILD_OPTS --with-ssl=${LIBPQ_TLS_CONFIGURE_NAME})
    endif()
    if("nls" IN_LIST FEATURES)
        set(ENV{MSGFMT} "${CURRENT_HOST_INSTALLED_DIR}/tools/gettext/bin/msgfmt${VCPKG_HOST_EXECUTABLE_SUFFIX}")
    endif()
    if("python" IN_LIST FEATURES)
        list(APPEND BUILD_OPTS --with-python=3.${PYTHON_VERSION_MINOR})
        vcpkg_find_acquire_program(PYTHON3)
        list(APPEND BUILD_OPTS "PYTHON=${PYTHON3}")
    endif()
    if(VCPKG_TARGET_IS_ANDROID AND (NOT VCPKG_CMAKE_SYSTEM_VERSION OR VCPKG_CMAKE_SYSTEM_VERSION LESS "26"))
        list(APPEND BUILD_OPTS ac_cv_header_langinfo_h=no)
    endif()
    if(VCPKG_DETECTED_CMAKE_OSX_SYSROOT)
        list(APPEND BUILD_OPTS "PG_SYSROOT=${VCPKG_DETECTED_CMAKE_OSX_SYSROOT}")
    endif()
    # The fixed 2023c MSYS2 tzcode archive no longer exists on any
    # published mirror. It is a *host-side* timezone-tool dependency for
    # PostgreSQL's optional client tools, not the libpq C client library.
    # Keep it when those tools are selected; never request a missing
    # archive for the ordinary libpq-only / no-ssl Studio build.
    vcpkg_list(SET _libpq_tool_tzcode)
    if(HAS_TOOLS)
        vcpkg_list(APPEND _libpq_tool_tzcode DIRECT_PACKAGES
            "https://mirror.msys2.org/msys/x86_64/tzcode-2023c-1-x86_64.pkg.tar.zst"
            7550b843964744607f736a7138f10c6cd92489406a1b84ac71d9a9d8aa16bc69048aa1b24e1f49291b010347047008194c334ca9c632e17fa8245e85549e3c7a)
    endif()
    vcpkg_configure_make(
        SOURCE_PATH "${SOURCE_PATH}"
        COPY_SOURCE
        AUTOCONFIG
        ADDITIONAL_MSYS_PACKAGES autoconf-archive
            ${_libpq_tool_tzcode}
        OPTIONS
            ${BUILD_OPTS}
        OPTIONS_DEBUG
            --enable-debug
    )

    if(VCPKG_LIBRARY_LINKAGE STREQUAL "dynamic")
        set(ENV{LIBPQ_LIBRARY_TYPE} shared)
    else()
        set(ENV{LIBPQ_LIBRARY_TYPE} static)
    endif()
    if(VCPKG_TARGET_IS_MINGW)
        set(ENV{LIBPQ_USING_MINGW} yes)
    endif()
    if(HAS_TOOLS)
        set(ENV{LIBPQ_ENABLE_TOOLS} yes)
    endif()
    vcpkg_install_make()

    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/postgresql/server/pg_config.h" "#define CONFIGURE_ARGS" "// #define CONFIGURE_ARGS")
    vcpkg_replace_string("${CURRENT_PACKAGES_DIR}/include/pg_config.h" "#define CONFIGURE_ARGS" "// #define CONFIGURE_ARGS")
endif()

vcpkg_fixup_pkgconfig()
configure_file("${CMAKE_CURRENT_LIST_DIR}/vcpkg-cmake-wrapper.cmake" "${CURRENT_PACKAGES_DIR}/share/postgresql/vcpkg-cmake-wrapper.cmake" @ONLY)

file(REMOVE_RECURSE
    "${CURRENT_PACKAGES_DIR}/debug/doc"
    "${CURRENT_PACKAGES_DIR}/debug/include"
    "${CURRENT_PACKAGES_DIR}/debug/share"
    "${CURRENT_PACKAGES_DIR}/debug/symbols"
    "${CURRENT_PACKAGES_DIR}/debug/tools"
    "${CURRENT_PACKAGES_DIR}/symbols"
    "${CURRENT_PACKAGES_DIR}/tools/${PORT}/debug"
)

file(INSTALL "${CURRENT_PORT_DIR}/usage" DESTINATION "${CURRENT_PACKAGES_DIR}/share/${PORT}")
vcpkg_install_copyright(FILE_LIST "${SOURCE_PATH}/COPYRIGHT")
