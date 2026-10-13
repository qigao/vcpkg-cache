/*
 * #192: private installed-GmSSL exact-version admission contract.
 * Never export TLS_CTX through Salts public ABI.
 */
#include <gmssl/tls.h>
#include <stdio.h>
#include <string.h>

static int check(int cond, const char *reason) {
    if (!cond) fprintf(stderr, "GmSSL strict version: %s\n", reason);
    return cond;
}

static int test_exact(int version, int cipher) {
    TLS_CTX ctx;
    int wrong_version = version == TLS_protocol_tlcp
        ? TLS_protocol_tls13 : TLS_protocol_tlcp;
    size_t count;
    int first;
    int result = 0;

    if (!check(tls_ctx_init(&ctx, version, TLS_client_mode) == 1,
               "context initialization failed")) return 0;
    count = ctx.supported_versions_cnt;
    first = ctx.supported_versions[0];

    if (!check(tls_ctx_set_strict_protocol(&ctx, wrong_version) != 1,
               "wrong protocol accepted") ||
        !check(ctx.supported_versions_cnt == count &&
               ctx.supported_versions[0] == first,
               "wrong protocol mutated existing versions") ||
        !check(tls_ctx_set_strict_protocol(&ctx, version) == 1,
               "correct protocol rejected") ||
        !check(ctx.protocol == version && ctx.min_protocol == version &&
               ctx.max_protocol == version &&
               ctx.supported_versions_cnt == 1u &&
               ctx.supported_versions[0] == version,
               "exact protocol was not enforced"))
        goto done;

    if (!check(tls_ctx_set_strict_protocol(&ctx, -1) != 1,
               "invalid protocol accepted") ||
        !check(ctx.supported_versions_cnt == 1u &&
               ctx.supported_versions[0] == version,
               "invalid protocol changed version offer") ||
        !check(tls_ctx_set_cipher_suites(&ctx, &cipher, 1u) == 1,
               "valid cipher rejected") ||
        !check(tls_ctx_set_strict_protocol(&ctx, version) != 1,
               "late protocol update accepted") ||
        !check(ctx.cipher_suites_cnt == 1u &&
               ctx.cipher_suites[0] == cipher &&
               ctx.supported_versions_cnt == 1u &&
               ctx.supported_versions[0] == version,
               "late protocol request mutated prior policy"))
        goto done;
    result = 1;
done:
    tls_ctx_cleanup(&ctx);
    return result;
}

static int test_range_is_not_strict(void) {
    TLS_CTX ctx;
    int result = 0;
    if (!check(tls_ctx_init(&ctx, TLS_protocol_tls13, TLS_client_mode) == 1,
               "range context failed")) return 0;
    if (!check(tls_ctx_set_protocol_range(&ctx, TLS_protocol_tls12,
                                          TLS_protocol_tls13) == 1,
               "validated standard TLS range failed"))
        goto done;
    if (!check(tls_ctx_set_strict_protocol(&ctx, TLS_protocol_tls13) != 1,
               "ambiguous range was silently narrowed") ||
        !check(ctx.min_protocol == TLS_protocol_tls12 &&
               ctx.max_protocol == TLS_protocol_tls13 &&
               ctx.supported_versions_cnt == 2u &&
               ctx.supported_versions[0] == TLS_protocol_tls13 &&
               ctx.supported_versions[1] == TLS_protocol_tls12,
               "rejected narrowing mutated range"))
        goto done;
    result = 1;
done:
    tls_ctx_cleanup(&ctx);
    return result;
}

int main(void) {
    if (!test_exact(TLS_protocol_tls13, TLS_cipher_sm4_gcm_sm3) ||
        !test_exact(TLS_protocol_tlcp, TLS_cipher_ecc_sm4_gcm_sm3) ||
        !test_exact(TLS_protocol_tls12,
                    TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256) ||
        !test_range_is_not_strict())
        return 1;
    puts("GmSSL private strict TLS/TLCP protocol contract: PASS");
    return 0;
}
