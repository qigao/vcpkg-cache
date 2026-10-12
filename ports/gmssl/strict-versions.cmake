# #192: CNet RFC 8998/TLCP exact-version admission over pinned GmSSL.
# Exported only by the private provider; never by Salts::Core/CNet.
# GmSSL upstream implements tls_ctx_set_supported_versions without declaring
# it in the installed public header. Restrict to one validated exact version.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_set_protocol_range(TLS_CTX *ctx, int min_protocol, int max_protocol);
int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt);
]==]
[==[
int tls_ctx_set_protocol_range(TLS_CTX *ctx, int min_protocol, int max_protocol);
/* Exact-version pre-configuration policy for TLS 1.2/1.3 or TLCP.
 * Valid only directly after tls_ctx_init and before other policy/keys.
 * On failure the provider context is not modified.
 */
int tls_ctx_set_strict_protocol(TLS_CTX *ctx, int protocol);
int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt);
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt)
]==]
[==[
int tls_ctx_set_strict_protocol(TLS_CTX *ctx, int protocol)
{
    if (!ctx
        || (protocol != TLS_protocol_tls13
            && protocol != TLS_protocol_tls12
            && protocol != TLS_protocol_tlcp)
        || ctx->protocol != protocol
        || ctx->min_protocol != protocol
        || ctx->max_protocol != protocol
        || ctx->cipher_suites_cnt != 0
        || ctx->supported_groups_cnt != 0
        || ctx->signature_algorithms_cnt != 0
        || ctx->x509_keys_cnt != 0) {
        error_print();
        return -1;
    }
    /* The internal GmSSL setter validates the sole element before
     * assignment; no mixed version list or partial mutation is admitted. */
    return tls_ctx_set_supported_versions(ctx, &protocol, 1);
}

int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt)
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
