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

# GmSSL is a private implementation dependency for consumers such as CNet.
# Force a static provider regardless of the triplet's default library linkage.
vcpkg_replace_string(
    "${SOURCE_PATH}/CMakeLists.txt"
    "add_library(gmssl \${src})"
    "add_library(gmssl STATIC \${src})"
)

include("${CMAKE_CURRENT_LIST_DIR}/portability.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/external-io.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/standard-tls.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/alpn-capacity.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/trust-anchors.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/tls-lifecycle.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/x509-compat.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/inspection.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/exporter.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/version-range.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/signature-capacity.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/ec-plain-pkcs8.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/rsa-verify.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/rsa-signatures.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/rsa-private.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/rsa-private-op.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/rsa-pkcs8.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/rsa-private-signatures.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/x509-rsa.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/x509-rsa-signing.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/rsa-encrypted-pkcs8.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/tls13-rsa.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/tls12-rsa.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/tls12-rsa-server-signing.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/tls12-rsa-mtls.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/tls13-rsa-signing.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/abi-contract.cmake")

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
