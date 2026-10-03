#include <gmssl/tls.h>

#include <stdio.h>

int main(void)
{
	TLS_CTX ctx;
	TLS_CTX server_ctx;
	TLS_CONNECT conn;
	const int cipher_suites[] = {
		TLS_cipher_aes_128_gcm_sha256,
		TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256,
	};
	const int group = TLS_curve_secp256r1;
	const int sig_algs[] = {
		TLS_sig_rsa_pss_rsae_sha256,
		TLS_sig_rsa_pkcs1_sha256,
		TLS_sig_ecdsa_secp256r1_sha256,
	};

	if (tls_ctx_init(&ctx, TLS_protocol_tls13, TLS_client_mode) != 1) return 1;
	if (tls_ctx_set_protocol_range(&ctx, TLS_protocol_tls12, TLS_protocol_tls13) != 1) return 2;
	if (ctx.min_protocol != TLS_protocol_tls12 || ctx.max_protocol != TLS_protocol_tls13) return 3;
	if (ctx.supported_versions_cnt != 2
		|| ctx.supported_versions[0] != TLS_protocol_tls13
		|| ctx.supported_versions[1] != TLS_protocol_tls12) return 4;
	if (tls_ctx_set_cipher_suites(&ctx, cipher_suites,
		sizeof(cipher_suites)/sizeof(cipher_suites[0])) != 1) return 5;
	if (tls_ctx_set_supported_groups(&ctx, &group, 1) != 1) return 6;
	if (tls_ctx_set_signature_algorithms(&ctx, sig_algs,
		sizeof(sig_algs)/sizeof(sig_algs[0])) != 1) return 7;
	if (ctx.signature_algorithms_cnt != 3
		|| ctx.signature_algorithms[0] != TLS_sig_rsa_pss_rsae_sha256
		|| ctx.signature_algorithms[1] != TLS_sig_rsa_pkcs1_sha256
		|| ctx.signature_algorithms[2] != TLS_sig_ecdsa_secp256r1_sha256) return 8;
	if (tls_init(&conn, &ctx) != 1) return 9;
	if (conn.protocol != TLS_protocol_tls13) return 13;
	tls_cleanup(&conn);
	tls_ctx_cleanup(&ctx);

	if (tls_ctx_init(&server_ctx, TLS_protocol_tls13, TLS_server_mode) != 1) return 10;
	if (tls_ctx_set_protocol_range(&server_ctx, TLS_protocol_tls12, TLS_protocol_tls13) == 1) return 11;
	tls_ctx_cleanup(&server_ctx);

	puts("GmSSL TLS client version-range contract: PASS");
	return 0;
}
