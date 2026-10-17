cmake_minimum_required(VERSION 3.16)
project(gmssl_tls12_alpn_contract C)

find_package(GmSSL CONFIG REQUIRED)

add_executable(gmssl-des-cbc-contract des-cbc-contract.c)
target_link_libraries(gmssl-des-cbc-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-des-cbc-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-des-cbc-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-des-cbc-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-sha1-contract sha1-contract.c)
target_link_libraries(gmssl-sha1-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-sha1-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-sha1-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-sha1-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls12-alpn-contract tls12-alpn-contract.c)
target_link_libraries(gmssl-tls12-alpn-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls12-alpn-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls12-alpn-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls12-alpn-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls-version-range-contract tls-version-range-contract.c)
target_link_libraries(gmssl-tls-version-range-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-version-range-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls-version-range-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls-version-range-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls-version-range-dispatch-contract tls-version-range-dispatch-contract.c)
target_link_libraries(gmssl-tls-version-range-dispatch-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-version-range-dispatch-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls-version-range-dispatch-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls-version-range-dispatch-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-public-contract rsa-public-contract.c)
target_link_libraries(gmssl-rsa-public-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-public-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-public-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-public-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-signature-contract rsa-signature-contract.c)
target_link_libraries(gmssl-rsa-signature-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-signature-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-signature-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-signature-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-x509-rsa-contract x509-rsa-contract.c)
target_link_libraries(gmssl-x509-rsa-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-x509-rsa-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-x509-rsa-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-x509-rsa-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-private-contract rsa-private-contract.c)
target_link_libraries(gmssl-rsa-private-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-private-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-private-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-private-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls13-rsa-pss-contract tls13-rsa-pss-contract.c)
target_link_libraries(gmssl-tls13-rsa-pss-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls13-rsa-pss-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls13-rsa-pss-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls13-rsa-pss-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-private-op-contract rsa-private-op-contract.c)
target_link_libraries(gmssl-rsa-private-op-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-private-op-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-private-op-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-private-op-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-pkcs8-contract rsa-pkcs8-contract.c)
target_link_libraries(gmssl-rsa-pkcs8-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-pkcs8-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-pkcs8-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-pkcs8-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-encrypted-pkcs8-contract rsa-encrypted-pkcs8-contract.c)
target_link_libraries(gmssl-rsa-encrypted-pkcs8-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-encrypted-pkcs8-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-encrypted-pkcs8-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-encrypted-pkcs8-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-private-signatures-contract rsa-private-signatures-contract.c)
target_link_libraries(gmssl-rsa-private-signatures-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-private-signatures-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-private-signatures-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-private-signatures-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls-exporter-contract tls-exporter-contract.c)
target_link_libraries(gmssl-tls-exporter-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-exporter-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls-exporter-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls-exporter-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls-inspection-contract tls-inspection-contract.c)
target_link_libraries(gmssl-tls-inspection-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-inspection-contract PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  target_compile_options(gmssl-tls-inspection-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(gmssl-tls-inspection-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls12-ecdhe-rsa-contract tls12-ecdhe-rsa-contract.c)
target_link_libraries(gmssl-tls12-ecdhe-rsa-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls12-ecdhe-rsa-contract PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
add_executable(gmssl-x509-basic-constraints-contract x509-basic-constraints-contract.c)
target_link_libraries(gmssl-x509-basic-constraints-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-x509-basic-constraints-contract PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
add_executable(gmssl-x509-ca-eku-contract x509-ca-eku-contract.c)
target_link_libraries(gmssl-x509-ca-eku-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-x509-ca-eku-contract PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
add_executable(gmssl-tls-certificate-capacity-contract tls-certificate-capacity-contract.c)
target_link_libraries(gmssl-tls-certificate-capacity-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-certificate-capacity-contract PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  target_compile_options(gmssl-tls12-ecdhe-rsa-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(gmssl-tls12-ecdhe-rsa-contract PRIVATE -fsanitize=address)
  target_compile_options(gmssl-x509-basic-constraints-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(gmssl-x509-basic-constraints-contract PRIVATE -fsanitize=address)
  target_compile_options(gmssl-x509-ca-eku-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(gmssl-x509-ca-eku-contract PRIVATE -fsanitize=address)
  target_compile_options(gmssl-tls-certificate-capacity-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(gmssl-tls-certificate-capacity-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls-version-range-server-dispatch-contract tls-version-range-server-dispatch-contract.c)
target_link_libraries(gmssl-tls-version-range-server-dispatch-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-version-range-server-dispatch-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls-version-range-server-dispatch-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls-version-range-server-dispatch-contract PRIVATE -fsanitize=address)
endif()

file(TO_CMAKE_PATH "${CMAKE_CURRENT_LIST_DIR}/fixtures/external-io-ca-cert.pem" _gmssl_external_io_ca)
file(TO_CMAKE_PATH "${CMAKE_CURRENT_LIST_DIR}/fixtures/external-io-server-cert.pem" _gmssl_external_io_cert)
file(TO_CMAKE_PATH "${CMAKE_CURRENT_LIST_DIR}/fixtures/external-io-server-key.pem" _gmssl_external_io_key)

function(gmssl_add_external_io_contract target protocol cipher sig_alg label)
    add_executable(${target} tls-external-io-contract.c)
    target_link_libraries(${target} PRIVATE GmSSL::GmSSL)
    target_compile_definitions(${target} PRIVATE
        "GMSSL_EXTERNAL_IO_CA_CERT=\"${_gmssl_external_io_ca}\""
        "GMSSL_EXTERNAL_IO_SERVER_CERT=\"${_gmssl_external_io_cert}\""
        "GMSSL_EXTERNAL_IO_SERVER_KEY=\"${_gmssl_external_io_key}\""
        "GMSSL_EXTERNAL_IO_PROTOCOL=${protocol}"
        "GMSSL_EXTERNAL_IO_CIPHER=${cipher}"
        "GMSSL_EXTERNAL_IO_SIGALG=${sig_alg}"
        "GMSSL_EXTERNAL_IO_LABEL=\"${label}\"")
    set_target_properties(${target} PROPERTIES
        C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
    if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
        target_compile_options(${target} PRIVATE -fsanitize=address -fno-omit-frame-pointer)
        target_link_options(${target} PRIVATE -fsanitize=address)
    endif()
endfunction()

gmssl_add_external_io_contract(
    gmssl-tls13-external-io-contract
    TLS_protocol_tls13
    TLS_cipher_aes_128_gcm_sha256
    TLS_sig_rsa_pss_rsae_sha256
    "TLS 1.3")
gmssl_add_external_io_contract(
    gmssl-tls12-external-io-contract
    TLS_protocol_tls12
    TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256
    TLS_sig_rsa_pkcs1_sha256
    "TLS 1.2")

unset(_gmssl_external_io_ca)
unset(_gmssl_external_io_cert)
unset(_gmssl_external_io_key)

add_executable(gmssl-p256-plain-pkcs8-contract p256-plain-pkcs8-contract.c)
target_link_libraries(gmssl-p256-plain-pkcs8-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-p256-plain-pkcs8-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-p256-plain-pkcs8-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-p256-plain-pkcs8-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-p256-ecdsa-der-contract p256-ecdsa-der-contract.c)
target_link_libraries(gmssl-p256-ecdsa-der-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-p256-ecdsa-der-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-p256-ecdsa-der-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-p256-ecdsa-der-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls-cleanup-contract tls-cleanup-contract.c)
target_link_libraries(gmssl-tls-cleanup-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-cleanup-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls-cleanup-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls-cleanup-contract PRIVATE -fsanitize=address)
endif()


# #192: test the *installed provider's* strict protocol ABI, not Salts TLS.
add_executable(gmssl-strict-protocol-contract strict-protocol-contract.c)
target_link_libraries(gmssl-strict-protocol-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-strict-protocol-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)

# The cache qualification workflow already builds this CMake project on
# host platforms. Make the conformance executable part of that native build
# gate instead of introducing a redundant CI target list.
if(NOT CMAKE_CROSSCOMPILING)
    add_custom_command(TARGET gmssl-strict-protocol-contract POST_BUILD
        COMMAND "$<TARGET_FILE:gmssl-strict-protocol-contract>"
        COMMENT "Qualify private GmSSL strict TLS/TLCP admission")
endif()

add_executable(gmssl-x509-p384-sha384-contract x509-p384-sha384-contract.c)
target_link_libraries(gmssl-x509-p384-sha384-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-x509-p384-sha384-contract PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
foreach(_gmssl_p384_fixture IN ITEMS p384-ca p384-leaf p256-ca p256-leaf)
    string(TOUPPER "${_gmssl_p384_fixture}" _gmssl_p384_name)
    string(REPLACE "-" "_" _gmssl_p384_name "${_gmssl_p384_name}")
    set(_gmssl_p384_file "${CMAKE_CURRENT_LIST_DIR}/fixtures/${_gmssl_p384_fixture}-sha384.pem")
    target_compile_definitions(gmssl-x509-p384-sha384-contract PRIVATE
        "GMSSL_${_gmssl_p384_name}=\"${_gmssl_p384_file}\"")
endforeach()
unset(_gmssl_p384_fixture)
unset(_gmssl_p384_name)
unset(_gmssl_p384_file)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-x509-p384-sha384-contract PRIVATE
        -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-x509-p384-sha384-contract PRIVATE -fsanitize=address)
endif()
enable_testing()
add_test(NAME gmssl.x509_p384_sha384 COMMAND gmssl-x509-p384-sha384-contract)
# The GmSSL overlay workflow builds this project on native runners but does not
# invoke CTest as a separate step on every OS: require the contract to execute.
if(NOT CMAKE_CROSSCOMPILING)
    add_custom_command(TARGET gmssl-x509-p384-sha384-contract POST_BUILD
        COMMAND "$<TARGET_FILE:gmssl-x509-p384-sha384-contract>"
        COMMENT "Verify private P-384 issuer / SHA-384 certificate chains")
endif()

# Consumer header/library ABI agreement under the exported feature macros.
add_executable(gmssl-tls-abi-layout-contract tls-abi-layout-contract.c)
target_link_libraries(gmssl-tls-abi-layout-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-abi-layout-contract PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
if(NOT CMAKE_CROSSCOMPILING)
    add_custom_command(TARGET gmssl-tls-abi-layout-contract POST_BUILD
        COMMAND "$<TARGET_FILE:gmssl-tls-abi-layout-contract>"
        COMMENT "Verify installed TLS_CTX and TLS_CONNECT header/library ABI sizes")
endif()
