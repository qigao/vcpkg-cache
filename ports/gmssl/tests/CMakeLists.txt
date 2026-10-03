cmake_minimum_required(VERSION 3.16)
project(gmssl_tls12_alpn_contract C)

find_package(GmSSL CONFIG REQUIRED)

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
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
  target_compile_options(gmssl-tls12-ecdhe-rsa-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(gmssl-tls12-ecdhe-rsa-contract PRIVATE -fsanitize=address)
  target_compile_options(gmssl-x509-basic-constraints-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
  target_link_options(gmssl-x509-basic-constraints-contract PRIVATE -fsanitize=address)
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

