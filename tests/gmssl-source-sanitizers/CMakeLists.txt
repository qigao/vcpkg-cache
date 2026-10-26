# Exact vcpkg-cache GmSSL source sanitizer conformance.
# There is no GmSSL source copy or private second build owner in Crypto.
cmake_minimum_required(VERSION 3.21)
project(GmSSLInstalledSanitizerConformance LANGUAGES C)
include(CTest)
find_package(Threads REQUIRED)

if(NOT DEFINED GMSSL_SANITIZED_PREFIX OR
   NOT EXISTS "${GMSSL_SANITIZED_PREFIX}/include/gmssl/tls.h")
  message(FATAL_ERROR "Expected installed, source-instrumented GmSSL vcpkg prefix")
endif()
find_package(GmSSL CONFIG REQUIRED
  PATHS "${GMSSL_SANITIZED_PREFIX}" NO_DEFAULT_PATH NO_CMAKE_FIND_ROOT_PATH)
if(NOT TARGET GmSSL::GmSSL)
  message(FATAL_ERROR "Missing installed source-sanitized GmSSL imported target")
endif()
get_target_property(_imported_archive GmSSL::GmSSL IMPORTED_LOCATION_RELEASE)
file(TO_CMAKE_PATH "${_imported_archive}" _imported_archive)
file(TO_CMAKE_PATH "${GMSSL_SANITIZED_PREFIX}/lib/libgmssl.a" _expected_archive)
if(NOT EXISTS "${_expected_archive}" OR
   NOT _imported_archive STREQUAL _expected_archive)
  message(FATAL_ERROR "Wrong or nonstatic GmSSL archive source owner")
endif()
set(_gmssl_tests "${CMAKE_CURRENT_LIST_DIR}/../../ports/gmssl/tests")
if(NOT EXISTS "${_gmssl_tests}/tls-abi-layout-contract.c")
  message(FATAL_ERROR "Missing original port-owned C11 contract sources")
endif()

function(crypto_gmssl_original_case case_name file_name)
  add_executable("crypto_original_${case_name}" "${_gmssl_tests}/${file_name}")
  set_target_properties("crypto_original_${case_name}" PROPERTIES
    C_STANDARD 11 C_STANDARD_REQUIRED ON C_EXTENSIONS OFF)
  target_link_libraries("crypto_original_${case_name}" PRIVATE
    GmSSL::GmSSL Threads::Threads "${CMAKE_DL_LIBS}")
  if(WIN32)
    target_link_libraries("crypto_original_${case_name}" PRIVATE Ws2_32)
  elseif(APPLE)
    target_link_libraries("crypto_original_${case_name}" PRIVATE "-framework Security")
  elseif(UNIX)
    target_link_libraries("crypto_original_${case_name}" PRIVATE m)
  endif()
  add_test(NAME "gmssl.original.${case_name}"
    COMMAND "crypto_original_${case_name}")
  set_tests_properties("gmssl.original.${case_name}" PROPERTIES TIMEOUT 60)
endfunction()

crypto_gmssl_original_case(tls_abi_layout tls-abi-layout-contract.c)
crypto_gmssl_original_case(p256_ecdsa_der p256-ecdsa-der-contract.c)
crypto_gmssl_original_case(rsa_public rsa-public-contract.c)
crypto_gmssl_original_case(tls_cleanup tls-cleanup-contract.c)
crypto_gmssl_original_case(x509_p384_sha384 x509-p384-sha384-contract.c)

foreach(_fixture IN ITEMS p384-ca p384-leaf p256-ca p256-leaf)
  string(TOUPPER "${_fixture}" _label)
  string(REPLACE "-" "_" _label "${_label}")
  set(_path "${_gmssl_tests}/fixtures/${_fixture}-sha384.pem")
  target_compile_definitions(crypto_original_x509_p384_sha384 PRIVATE
    "GMSSL_${_label}=\"${_path}\"")
endforeach()

# Original, unchanged C11 GmSSL 3.2 contract sources: test-only binary
# imports the exact privately assembled libgmssl.a, never an exported API.
foreach(_entry IN ITEMS
    des_cbc:des-cbc-contract.c
    sha1:sha1-contract.c
    tls12_alpn:tls12-alpn-contract.c
    tls_version_range:tls-version-range-contract.c
    tls_version_range_dispatch:tls-version-range-dispatch-contract.c
    tls_version_range_server_dispatch:tls-version-range-server-dispatch-contract.c
    rsa_signature:rsa-signature-contract.c
    x509_rsa:x509-rsa-contract.c
    rsa_private:rsa-private-contract.c
    tls13_rsa_pss:tls13-rsa-pss-contract.c
    rsa_private_op:rsa-private-op-contract.c
    rsa_pkcs8:rsa-pkcs8-contract.c
    rsa_encrypted_pkcs8:rsa-encrypted-pkcs8-contract.c
    rsa_private_signatures:rsa-private-signatures-contract.c
    tls_exporter:tls-exporter-contract.c
    tls_inspection:tls-inspection-contract.c
    tls12_ecdhe_rsa:tls12-ecdhe-rsa-contract.c
    x509_basic_constraints:x509-basic-constraints-contract.c
    x509_ca_eku:x509-ca-eku-contract.c
    tls_certificate_capacity:tls-certificate-capacity-contract.c
    p256_plain_pkcs8:p256-plain-pkcs8-contract.c
    strict_protocol:strict-protocol-contract.c)
  string(REPLACE ":" ";" _fields "${_entry}")
  list(GET _fields 0 _name)
  list(GET _fields 1 _source)
  crypto_gmssl_original_case("${_name}" "${_source}")
endforeach()

# True original TLS 1.2 and TLS 1.3 external-I/O contracts. This executes
# real borrowed callbacks and TLS handshake state, not a mocked transcript.
function(crypto_original_external_io case_name protocol cipher sigalg label)
  crypto_gmssl_original_case("${case_name}" "tls-external-io-contract.c")
  set(_target "crypto_original_${case_name}")
  target_compile_definitions("${_target}" PRIVATE
    "GMSSL_EXTERNAL_IO_CA_CERT=\"${_gmssl_tests}/fixtures/external-io-ca-cert.pem\""
    "GMSSL_EXTERNAL_IO_SERVER_CERT=\"${_gmssl_tests}/fixtures/external-io-server-cert.pem\""
    "GMSSL_EXTERNAL_IO_SERVER_KEY=\"${_gmssl_tests}/fixtures/external-io-server-key.pem\""
    "GMSSL_EXTERNAL_IO_PROTOCOL=${protocol}"
    "GMSSL_EXTERNAL_IO_CIPHER=${cipher}"
    "GMSSL_EXTERNAL_IO_SIGALG=${sigalg}"
    "GMSSL_EXTERNAL_IO_LABEL=\"${label}\"")
  set_tests_properties("gmssl.original.${case_name}" PROPERTIES TIMEOUT 120)
endfunction()
crypto_original_external_io(tls13_external_io
  TLS_protocol_tls13 TLS_cipher_aes_128_gcm_sha256
  TLS_sig_rsa_pss_rsae_sha256 "TLS 1.3")
crypto_original_external_io(tls12_external_io
  TLS_protocol_tls12 TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256
  TLS_sig_rsa_pkcs1_sha256 "TLS 1.2")
