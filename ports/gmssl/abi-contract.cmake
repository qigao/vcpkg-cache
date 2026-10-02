# Expose runtime size probes for GmSSL's caller-owned public TLS structs.
# Their layout depends on public feature macros, so the package must be able to
# prove that consumer headers and the compiled library agree.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

vcpkg_replace_string(
    "${_gmssl_tls_h}"
    "int tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client);"
    "size_t tls_ctx_sizeof(void);\nint tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client);"
)

vcpkg_replace_string(
    "${_gmssl_tls_h}"
    "int tls_init(TLS_CONNECT *conn, TLS_CTX *ctx);"
    "size_t tls_connect_sizeof(void);\nint tls_init(TLS_CONNECT *conn, TLS_CTX *ctx);"
)

vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "int tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client)\n{"
    "size_t tls_ctx_sizeof(void)\n{\n\treturn sizeof(TLS_CTX);\n}\n\nint tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client)\n{"
)

vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "int tls_init(TLS_CONNECT *conn, TLS_CTX *ctx)\n{"
    "size_t tls_connect_sizeof(void)\n{\n\treturn sizeof(TLS_CONNECT);\n}\n\nint tls_init(TLS_CONNECT *conn, TLS_CTX *ctx)\n{"
)
