# TLS Certificate messages commonly exceed 4 KiB with modern public-PKI chains.
# Match TLS_CTX's existing 8 KiB certificate-chain storage while keeping
# TLS_CONNECT bounded.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")

gmssl_replace_once(
    "${_gmssl_tls_h}"
    "#define TLS_MAX_CERTIFICATES_SIZE\t4096"
    "#define TLS_MAX_CERTIFICATES_SIZE\t8192"
)

file(READ "${_gmssl_tls_h}" _gmssl_certificate_capacity_after)
string(FIND "${_gmssl_certificate_capacity_after}"
    "#define TLS_MAX_CERTIFICATES_SIZE\t8192"
    _gmssl_certificate_capacity_offset)
if(_gmssl_certificate_capacity_offset EQUAL -1)
    message(FATAL_ERROR "GmSSL TLS certificate-chain capacity adaptation missing")
endif()

unset(_gmssl_certificate_capacity_offset)
unset(_gmssl_certificate_capacity_after)
unset(_gmssl_tls_h)
