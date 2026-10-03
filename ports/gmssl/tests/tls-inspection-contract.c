#include <gmssl/tls.h>
#include <gmssl/x509.h>

#include <stdio.h>
#include <string.h>

int main(void)
{
	TLS_CONNECT conn;
	int complete = -1;
	int protocol = 0;
	int cipher_suite = 0;
	int verify_result = -1;
	int close_notify = -1;
	const char *cipher_name = NULL;
	const char *alpn = NULL;
	size_t alpn_len = 0;
	const uint8_t *chain = NULL;
	size_t chain_len = 0;
	uint8_t fingerprint[32] = {0};

	memset(&conn, 0, sizeof(conn));

	if (tls_get_handshake_complete(&conn, &complete) != 1 || complete != 0) return 1;
	if (tls_get_negotiated_protocol(&conn, &protocol) != 0) return 2;
	if (tls_get_negotiated_cipher_suite(&conn, &cipher_suite) != 0) return 3;
	if (tls_get_selected_alpn(&conn, &alpn, &alpn_len) != 0) return 4;
	if (tls_get_peer_certificate_chain(&conn, &chain, &chain_len) != 0) return 5;
	if (tls_get_peer_certificate_sha256(&conn, fingerprint) != 0) return 6;
	if (tls_get_verify_result(&conn, &verify_result) != 0) return 7;
	if (tls_get_peer_close_notify(&conn, &close_notify) != 1 || close_notify != 0) return 8;

	conn.handshake_state = TLS_state_handshake_over;
	conn.protocol = TLS_protocol_tls13;
	conn.cipher_suite = TLS_cipher_aes_128_gcm_sha256;
	conn.alpn_selected = "h2";
	conn.verify_result = X509_verify_ok;
	conn.close_notify_received = 1;

	if (tls_get_handshake_complete(&conn, &complete) != 1 || complete != 1) return 9;
	if (tls_get_negotiated_protocol(&conn, &protocol) != 1
		|| protocol != TLS_protocol_tls13) return 10;
	if (tls_get_negotiated_cipher_suite(&conn, &cipher_suite) != 1
		|| cipher_suite != TLS_cipher_aes_128_gcm_sha256) return 11;
	if (tls_get_negotiated_cipher_name(&conn, &cipher_name) != 1
		|| !cipher_name || strcmp(cipher_name, "TLS_AES_128_GCM_SHA256") != 0) return 12;
	if (tls_get_selected_alpn(&conn, &alpn, &alpn_len) != 1
		|| alpn_len != 2 || memcmp(alpn, "h2", 2) != 0) return 13;
	if (tls_get_verify_result(&conn, &verify_result) != 1
		|| verify_result != X509_verify_ok) return 14;
	if (tls_get_peer_close_notify(&conn, &close_notify) != 1 || close_notify != 1) return 15;

	puts("GmSSL TLS inspection contract: PASS");
	return 0;
}
