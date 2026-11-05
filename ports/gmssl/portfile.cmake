vcpkg_from_git(
    OUT_SOURCE_PATH SOURCE_PATH
    URL "https://github.com/guanzhi/GmSSL.git"
    REF 7c9f02904ef33e59c87b4f16621cc8fd434e7579
    PATCHES
        p256-ecdsa-der-signature-parsing.patch
        shangmi-secret-cleanup.patch
        sm2-uncompressed-point-validation.patch
        sm9-state-cleanup.patch
        tlcp-signature-extension.patch
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

# Extensions are source-owned by qigao/salts-core/crypto/gmssl-extensions.
# Fetch their exact immutable source commit only; vcpkg builds them exactly
# once into this one static GmSSL archive. Downstream Salts::Crypto LINKS the
# installed GmSSL target and MUST NOT compile a duplicate native source tree.
vcpkg_from_git(
    OUT_SOURCE_PATH GMSSL_CRYPTO_REPO
    URL "https://github.com/qigao/salts-core.git"
    REF 720abc55eca41cc7f676d0b5dbb38e8605d091b9
)
set(GMSSL_CRYPTO_EXTENSIONS_SOURCE
    "${GMSSL_CRYPTO_REPO}/crypto/gmssl-extensions")
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
vcpkg_apply_patches(
    SOURCE_PATH "${SOURCE_PATH}"
    PATCHES
        "${CMAKE_CURRENT_LIST_DIR}/tls12-range-negotiation.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls13-key-update-response.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls13-peer-key-update-limit.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls-memory-credentials.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls13-cipher-version-filter.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls-signature-policy.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls-multiple-memory-identities.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls-sni-dns-names.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls13-hrr-padding.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls-client-identity-selection.patch"
        "${CMAKE_CURRENT_LIST_DIR}/tls-certificate-signatures.patch"
        "${CMAKE_CURRENT_LIST_DIR}/pkcs8-aes-key-sizes.patch"
        "${CMAKE_CURRENT_LIST_DIR}/x509-validity-diagnostics.patch"
)

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
        -DENABLE_SM9=ON
        -DENABLE_CMS=ON
        -DENABLE_LMS=OFF
        -DENABLE_XMSS=OFF
        -DENABLE_SPHINCS=OFF
        -DENABLE_KYBER=OFF
        -DENABLE_ZUC=ON
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
