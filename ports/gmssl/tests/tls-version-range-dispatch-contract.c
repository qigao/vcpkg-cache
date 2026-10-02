#include <gmssl/tls.h>

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

typedef struct probe_io {
	uint8_t input[TLS_MAX_RECORD_SIZE];
	size_t input_len;
	size_t input_off;
	uint8_t output[TLS_MAX_RECORD_SIZE];
	size_t output_len;
} probe_io;

static tls_ret_t probe_send(void *user, const void *buf, size_t len, int flags)
{
	probe_io *io = (probe_io *)user;
	(void)flags;
	if (!io || !buf || len > sizeof(io->output) - io->output_len) {
		return TLS_ERROR_SYSCALL;
	}
	memcpy(io->output + io->output_len, buf, len);
	io->output_len += len;
	return (tls_ret_t)len;
}

static tls_ret_t probe_recv(void *user, void *buf, size_t len, int flags)
{
	probe_io *io = (probe_io *)user;
	size_t available;
	(void)flags;
	if (!io || !buf) return TLS_ERROR_SYSCALL;
	available = io->input_len - io->input_off;
	if (!available) return TLS_ERROR_RECV_AGAIN;
	if (len > available) len = available;
	memcpy(buf, io->input + io->input_off, len);
	io->input_off += len;
	return (tls_ret_t)len;
}

static int has_cipher(const uint8_t *data, size_t len, int wanted)
{
	while (len) {
		uint16_t value;
		if (tls_uint16_from_bytes(&value, &data, &len) != 1) return 0;
		if ((int)value == wanted) return 1;
	}
	return 0;
}

static int client_hello_has_range(const uint8_t *record)
{
	int legacy_version;
	const uint8_t *random;
	const uint8_t *session_id;
	size_t session_id_len;
	const uint8_t *cipher_suites;
	size_t cipher_suites_len;
	const uint8_t *exts;
	size_t exts_len;
	int saw_versions = 0;
	int saw_alpn = 0;

	if (tls_record_get_handshake_client_hello(
			record, &legacy_version, &random, &session_id, &session_id_len,
			&cipher_suites, &cipher_suites_len, &exts, &exts_len) != 1) return 0;
	if (legacy_version != TLS_protocol_tls12) return 0;
	if (!has_cipher(cipher_suites, cipher_suites_len, TLS_cipher_aes_128_gcm_sha256)
		|| !has_cipher(cipher_suites, cipher_suites_len,
			TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256)) return 0;

	while (exts_len) {
		int type;
		const uint8_t *data;
		size_t data_len;
		if (tls_ext_from_bytes(&type, &data, &data_len, &exts, &exts_len) != 1) return 0;
		if (type == TLS_extension_supported_versions) {
			const uint8_t *versions;
			size_t versions_len;
			uint16_t v1;
			uint16_t v2;
			if (saw_versions
				|| tls_uint8array_from_bytes(&versions, &versions_len, &data, &data_len) != 1
				|| tls_uint16_from_bytes(&v1, &versions, &versions_len) != 1
				|| tls_uint16_from_bytes(&v2, &versions, &versions_len) != 1
				|| versions_len != 0
				|| data_len != 0
				|| v1 != TLS_protocol_tls13
				|| v2 != TLS_protocol_tls12) return 0;
			saw_versions = 1;
		} else if (type == TLS_extension_application_layer_protocol_negotiation) {
			const uint8_t *names;
			size_t names_len;
			const uint8_t *name;
			size_t name_len;
			if (tls_application_layer_protocol_negotiation_from_bytes(
					&names, &names_len, data, data_len) != 1
				|| tls_uint8array_from_bytes(&name, &name_len, &names, &names_len) != 1
				|| name_len != 2 || memcmp(name, "h2", 2) != 0) return 0;
			saw_alpn = 1;
		}
	}
	return saw_versions && saw_alpn;
}

static int build_tls12_server_hello(uint8_t *record, size_t *record_len)
{
	uint8_t random[32] = {0};
	uint8_t exts[64];
	uint8_t *p = exts;
	size_t exts_len = 0;
	char *selected_alpn = "h2";

	random[31] = 7;
	memset(record, 0, TLS_MAX_RECORD_SIZE);
	if (tls_application_layer_protocol_negotiation_selected_ext_to_bytes(
			selected_alpn, &p, &exts_len) != 1) return -1;
	if (tls_record_set_protocol(record, TLS_protocol_tls12) != 1
		|| tls_record_set_handshake_server_hello(
			record, record_len, TLS_protocol_tls12, random, NULL, 0,
			TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256,
			exts, exts_len) != 1
		|| tls_record_set_protocol(record, TLS_protocol_tls12) != 1) return -1;
	return 1;
}

int main(void)
{
	TLS_CTX ctx;
	TLS_CONNECT conn;
	probe_io io = {0};
	TLS_IO callbacks = {&io, probe_send, probe_recv};
	const int cipher_suites[] = {
		TLS_cipher_aes_128_gcm_sha256,
		TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256,
	};
	const int group = TLS_curve_secp256r1;
	const int sig_alg = TLS_sig_ecdsa_secp256r1_sha256;
	char *alpn[] = {"h2", "http/1.1"};
	size_t server_hello_len = 0;
	int ret;
	int rc = 1;

	if (tls_ctx_init(&ctx, TLS_protocol_tls13, TLS_client_mode) != 1
		|| tls_ctx_set_protocol_range(&ctx, TLS_protocol_tls12, TLS_protocol_tls13) != 1
		|| tls_ctx_set_cipher_suites(&ctx, cipher_suites,
			sizeof(cipher_suites)/sizeof(cipher_suites[0])) != 1
		|| tls_ctx_set_supported_groups(&ctx, &group, 1) != 1
		|| tls_ctx_set_signature_algorithms(&ctx, &sig_alg, 1) != 1
		|| tls_ctx_set_application_layer_protocol_negotiation(&ctx, alpn, 2) != 1
		|| tls_init(&conn, &ctx) != 1
		|| tls_set_io(&conn, &callbacks) != 1) {
		return 2;
	}

	ret = tls_do_handshake(&conn);
	if (ret != TLS_ERROR_RECV_AGAIN) {
		rc = 3;
		goto end;
	}
	if (!io.output_len || !client_hello_has_range(io.output)) {
		rc = 4;
		goto end;
	}
	if (build_tls12_server_hello(io.input, &server_hello_len) != 1) {
		rc = 5;
		goto end;
	}
	io.input_len = server_hello_len;
	io.input_off = 0;

	ret = tls_do_handshake(&conn);
	if (ret != TLS_ERROR_RECV_AGAIN) {
		rc = 6;
		goto end;
	}
	if (conn.protocol != TLS_protocol_tls12
		|| conn.handshake_state != TLS_state_server_certificate) {
		rc = 7;
		goto end;
	}
	if (!conn.alpn_selected || strcmp(conn.alpn_selected, "h2") != 0) {
		rc = 8;
		goto end;
	}

	/* No additional input: the next dispatch must stay in the TLS 1.2
	 * server-certificate state and ask for more ciphertext. */
	ret = tls_do_handshake(&conn);
	if (ret != TLS_ERROR_RECV_AGAIN
		|| conn.protocol != TLS_protocol_tls12
		|| conn.handshake_state != TLS_state_server_certificate) {
		rc = 9;
		goto end;
	}

	rc = 0;
	puts("GmSSL TLS 1.2 fallback on one connection: PASS");

end:
	tls_cleanup(&conn);
	tls_ctx_cleanup(&ctx);
	return rc;
}
