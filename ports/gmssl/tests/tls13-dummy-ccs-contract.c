/* Regression for RFC 8446 D.4 dummy ChangeCipherSpec in GmSSL's
 * private TLS1.3 encrypted-handshake reader.
 *
 * This deliberately exercises exact record bytes, duplicate/flood bounds,
 * partial-fragment ownership, and public header versus compiled ABI size.
 * The full OpenSSL/GmSSL wire handshake remains a SEPARATE acceptance gate.
 */
#include "../tls13-compat-ccs.h"
#include <gmssl/tls.h>
#include <stdio.h>
#include <stddef.h>
#include <stdint.h>

#define CHECK(c) do { if (!(c)) {     fprintf(stderr, "GmSSL CCS contract failed at line %d: %s\n",             __LINE__, #c);     return 1; } } while (0)

int main(void)
{
    static const uint8_t good[6] = {0x14, 0x03, 0x03, 0, 1, 1};
    static const uint8_t ordinary_application_data[6] =
        {0x17, 0x03, 0x03, 0, 1, 1};
    uint8_t invalid[6];
    unsigned int seen = 0u;
    size_t i;

    /* Installed GmSSL public TLS_CONNECT and actual static library must
     * agree, because this change adds one owned generation-local field. */
    CHECK(sizeof(TLS_CONNECT) == tls_connect_sizeof());

    CHECK(gmssl_tls13_compat_ccs_admit(
        ordinary_application_data, sizeof(ordinary_application_data),
        0u, 0u, &seen) == 0 && seen == 0u);
    CHECK(gmssl_tls13_compat_ccs_admit(
        good, sizeof(good), 0u, 0u, &seen) == 1 && seen == 1u);
    /* Repeated/streaming pseudo-CCS can never consume unbounded work. */
    CHECK(gmssl_tls13_compat_ccs_admit(
        good, sizeof(good), 0u, 0u, &seen) == -1 && seen == 1u);

    for (i = 0u; i < sizeof(good); ++i) {
        size_t len;
        seen = 0u;
        for (len = 0u; len < sizeof(good); ++len)
            invalid[len] = good[len];
        invalid[i] ^= 1u;
        if (i == 0u) {
            /* non-CCS content is not consumed by this parser */
            CHECK(gmssl_tls13_compat_ccs_admit(
                invalid, sizeof(invalid), 0u, 0u, &seen) == 0);
        } else {
            CHECK(gmssl_tls13_compat_ccs_admit(
                invalid, sizeof(invalid), 0u, 0u, &seen) == -1);
        }
        CHECK(seen == 0u);
    }

    for (i = 1u; i < sizeof(good); ++i) {
        seen = 0u;
        CHECK(gmssl_tls13_compat_ccs_admit(good, i, 0u, 0u, &seen) == -1);
        CHECK(seen == 0u);
    }
    seen = 0u;
    CHECK(gmssl_tls13_compat_ccs_admit(
        good, sizeof(good), 1u, 0u, &seen) == -1);
    CHECK(gmssl_tls13_compat_ccs_admit(
        good, sizeof(good), 0u, 1u, &seen) == -1);
    CHECK(seen == 0u);
    CHECK(gmssl_tls13_compat_ccs_admit(
        NULL, sizeof(good), 0u, 0u, &seen) == -1);
    CHECK(gmssl_tls13_compat_ccs_admit(
        good, sizeof(good), 0u, 0u, NULL) == -1);
    CHECK(seen == 0u);
    puts("gmssl.tls13_dummy_ccs_contract: PASS");
    return 0;
}
