/* Apache-2.0; test-only public certificate fixtures generated independently. */
#include <gmssl/x509_cer.h>
#include <gmssl/x509_key.h>
#include <gmssl/oid.h>
#include <gmssl/tls.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

#ifndef GMSSL_P384_CA
#error "GMSSL_P384_CA path must be configured"
#endif
#ifndef GMSSL_P384_LEAF
#error "GMSSL_P384_LEAF path must be configured"
#endif
#ifndef GMSSL_P256_CA
#error "GMSSL_P256_CA path must be configured"
#endif
#ifndef GMSSL_P256_LEAF
#error "GMSSL_P256_LEAF path must be configured"
#endif

static int read_cert(const char *path, uint8_t *cert, size_t *len, size_t capacity)
{
    FILE *fp = fopen(path, "rb");
    int rc;
    if (!fp) return -1;
    *len = 0;
    rc = x509_cert_from_pem(cert, len, capacity, fp);
    if (fclose(fp) != 0) return -1;
    return rc == 1 ? 0 : -1;
}

int main(void)
{
    uint8_t ca384[4096], leaf384[4096], ca256[4096], leaf256[4096];
    uint8_t modified[4096];
    size_t nca384, nleaf384, nca256, nleaf256;
    X509_KEY ca_key = {0}, leaf_key = {0}, ca256_key = {0};
    int oid = OID_undef;

    if (read_cert(GMSSL_P384_CA, ca384, &nca384, sizeof(ca384)) != 0) return 1;
    if (read_cert(GMSSL_P384_LEAF, leaf384, &nleaf384, sizeof(leaf384)) != 0) return 2;
    if (read_cert(GMSSL_P256_CA, ca256, &nca256, sizeof(ca256)) != 0) return 3;
    if (read_cert(GMSSL_P256_LEAF, leaf256, &nleaf256, sizeof(leaf256)) != 0) return 4;

    if (x509_cert_get_subject_public_key(ca384, nca384, &ca_key) != 1
        || ca_key.algor != OID_ec_public_key
        || ca_key.algor_param != OID_secp384r1) return 5;
    if (x509_cert_get_subject_public_key(leaf384, nleaf384, &leaf_key) != 1
        || leaf_key.algor != OID_ec_public_key
        || leaf_key.algor_param != OID_secp256r1) return 6;
    if (x509_cert_get_subject_public_key(ca256, nca256, &ca256_key) != 1
        || ca256_key.algor_param != OID_secp256r1) return 7;
    if (x509_cert_get_signature_algor(leaf384, nleaf384, &oid) != 1
        || oid != OID_ecdsa_with_sha384) return 8;
    if (x509_cert_get_signature_algor(leaf256, nleaf256, &oid) != 1
        || oid != OID_ecdsa_with_sha384) return 9;
    if (x509_key_supports_sign_algor(&ca_key, OID_ecdsa_with_sha384) != 1
        || x509_key_supports_sign_algor(&ca_key, OID_ecdsa_with_sha256) != 0
        || x509_key_supports_sign_algor(&ca256_key, OID_ecdsa_with_sha384) != 1) return 10;

    /* Certificate SHA384 is selected from CA curve, independently of leaf P256. */
    if (tls_signature_scheme_from_algorithm_and_group_oid(
            OID_ecdsa_with_sha384, OID_secp384r1) != TLS_sig_ecdsa_secp384r1_sha384)
        return 17;
    if (tls_signature_scheme_algorithm_oid(TLS_sig_ecdsa_secp384r1_sha384)
            != OID_ecdsa_with_sha384
        || tls_signature_scheme_group_oid(TLS_sig_ecdsa_secp384r1_sha384)
            != OID_secp384r1)
        return 18;
    if (tls_signature_scheme_from_algorithm_and_group_oid(
            OID_ecdsa_with_sha384, OID_secp256r1) != 0)
        return 19;
    {
        TLS_CTX tls_ctx = {0};
        const int schemes[] = { TLS_sig_ecdsa_secp256r1_sha256,
                                TLS_sig_ecdsa_secp384r1_sha384 };
        if (tls_ctx_init(&tls_ctx, TLS_protocol_tls13, TLS_client_mode) != 1)
            return 20;
        if (tls_ctx_set_signature_algorithms(&tls_ctx, schemes, 2) != 1)
            return 21;
        tls_ctx_cleanup(&tls_ctx);
    }

    /* Prove the genuine SHA384 signed P256 server leaf by P384 issuer. */
    if (x509_cert_verify_by_ca_cert(leaf384, nleaf384, ca384, nca384, NULL, 0) != 1) return 11;
    /* Also cover issuer P256 with an ECDSA/SHA384 signature: digest != curve. */
    if (x509_cert_verify_by_ca_cert(leaf256, nleaf256, ca256, nca256, NULL, 0) != 1) return 12;

    /* Independently signed chains must not cross-verify. */
    if (x509_cert_verify_by_ca_cert(leaf384, nleaf384, ca256, nca256, NULL, 0) == 1) return 13;
    if (x509_cert_verify_by_ca_cert(leaf256, nleaf256, ca384, nca384, NULL, 0) == 1) return 14;

    /* Tamper the DER signature bytes, preserving overall certificate syntax. */
    memcpy(modified, leaf384, nleaf384);
    modified[nleaf384 - 1] ^= 0x01;
    if (x509_cert_verify_by_ca_cert(modified, nleaf384, ca384, nca384, NULL, 0) == 1) return 15;
    memcpy(modified, leaf256, nleaf256);
    modified[nleaf256 - 1] ^= 0x01;
    if (x509_cert_verify_by_ca_cert(modified, nleaf256, ca256, nca256, NULL, 0) == 1) return 16;

    x509_key_cleanup(&ca256_key);
    x509_key_cleanup(&leaf_key);
    x509_key_cleanup(&ca_key);
    puts("GmSSL P-384 CA / P-256 leaf ECDSA-SHA384 X.509 verification: PASS");
    return 0;
}
