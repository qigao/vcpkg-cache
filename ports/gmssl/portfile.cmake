vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL "https://github.com/guanzhi/GmSSL.git"
    REF 7c9f02904ef33e59c87b4f16621cc8fd434e7579
    PATCHES
        p256-ecdsa-der-signature-parsing.patch
)

# Upstream overrides CMAKE_INSTALL_PREFIX on MSVC. vcpkg owns the install root.
vcpkg_replace_string(
    "${SOURCE_PATH}/CMakeLists.txt"
    "set(CMAKE_INSTALL_PREFIX \"C:/Program Files/GmSSL\")"
    "# CMAKE_INSTALL_PREFIX is provided by vcpkg"
)

# Static GmSSL is the single vcpkg-source owner for TLS and algorithms.
# Force a static provider regardless of the triplet's default library linkage.
vcpkg_replace_string(
    "${SOURCE_PATH}/CMakeLists.txt"
    "add_library(gmssl \${src})"
    "add_library(gmssl STATIC \${src})"
)

# Native C/H extensions live solely in qigao/crypto.
# This is a pinned SOURCE-ONLY fetch, not a second GmSSL package dependency.
# vcpkg builds these same sources once into its GmSSL static archive; the
# installed Salts::Crypto later embeds that archive, without rebuilding them.
vcpkg_from_git(
    OUT_SOURCE_PATH GMSSL_CRYPTO_REPO
    URL "https://github.com/qigao/crypto.git"
    REF d88d90dfd81df2320e6d47a92ad58c1eac9e0a17
)
set(GMSSL_CRYPTO_EXTENSIONS_SOURCE
    "${GMSSL_CRYPTO_REPO}/vendor/gmssl-extensions")
foreach(_gmssl_extension IN ITEMS
    src/aes_key_wrap.c
    src/des.c
    src/md5.c
    src/rsa_ext.c
    src/rsa_private_op.c
    src/secp384r1_verify.c
    src/tls13-handshake-reader.h
    include/gmssl/aes_key_wrap.h
    include/gmssl/des.h
    include/gmssl/md5.h
    include/gmssl/rsa_components.h
    include/gmssl/rsa_ext.h
    include/gmssl/secp384r1_verify.h)
    if(NOT EXISTS "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/${_gmssl_extension}")
        message(FATAL_ERROR
            "Pinned Crypto GmSSL extension source missing: ${_gmssl_extension}")
    endif()
endforeach()
unset(_gmssl_extension)

# Source adaptations are consolidated into four ordered, port-owned phases.
# They preserve the exact historical transform order and fail-closed anchors.
include("${CMAKE_CURRENT_LIST_DIR}/overlays-01.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/overlays-02.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/overlays-03.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/overlays-04.cmake")

vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        -DENABLE_TLS=ON
        -DENABLE_SECP256R1=ON
        -DENABLE_SHA2=ON
        -DENABLE_AES=ON
        -DENABLE_AES_CCM=OFF
        -DENABLE_SHA1=ON
        -DENABLE_CHACHA20=OFF
        -DENABLE_GHASH=OFF
        -DENABLE_SM9=OFF
        -DENABLE_CMS=OFF
        -DENABLE_LMS=OFF
        -DENABLE_XMSS=OFF
        -DENABLE_SPHINCS=OFF
        -DENABLE_KYBER=OFF
        -DENABLE_ZUC=OFF
        -DENABLE_SKF=OFF
        -DENABLE_SDF=OFF
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
