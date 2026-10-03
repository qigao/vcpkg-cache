#include <gmssl/tls.h>
#include <gmssl/block_cipher.h>
#include <gmssl/digest.h>

#include <stdio.h>
#include <string.h>

int main(void)
{
	TLS_CTX ctx;
	TLS_CONNECT conn;
	const BLOCK_CIPHER *cipher = NULL;
	const DIGEST *digest = NULL;
	const int cipher_suite = TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256;
	const int group = TLS_curve_secp256r1;
	const int sig_alg = TLS_sig_rsa_pkcs1_sha256;

	if (tls_cipher_suite_from_name("TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256") != cipher_suite) return 1;
	if (strcmp(tls_cipher_suite_name(cipher_suite), "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256") != 0) return 2;
	if (tls_signature_scheme_from_name("rsa_pkcs1_sha256") != sig_alg) return 3;
	if (tls_signature_scheme_match_cipher_suite(sig_alg, cipher_suite) != 1) return 4;
	if (tls_cipher_suite_get(cipher_suite, &cipher, &digest) != 1) return 5;
	if (!cipher || !digest || digest->oid != OID_sha256) return 6;

	if (tls_ctx_init(&ctx, TLS_protocol_tls12, TLS_client_mode) != 1) return 7;
	if (tls_ctx_set_cipher_suites(&ctx, &cipher_suite, 1) != 1) return 8;
	if (tls_ctx_set_supported_groups(&ctx, &group, 1) != 1) return 9;
	if (tls_ctx_set_signature_algorithms(&ctx, &sig_alg, 1) != 1) return 10;
	if (tls_init(&conn, &ctx) != 1) return 11;
	if (conn.protocol != TLS_protocol_tls12) return 12;

	tls_cleanup(&conn);
	tls_ctx_cleanup(&ctx);
	puts("GmSSL TLS 1.2 ECDHE_RSA mapping contract: PASS");
	return 0;
}
