#include <gmssl/tls.h>

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

extern int tls13_do_server_handshake(TLS_CONNECT *conn);

typedef struct probe_io {
	uint8_t input[TLS_MAX_RECORD_SIZE];
	size_t input_len;
	size_t input_off;
} probe_io;

static tls_ret_t probe_send(void *user, const void *buf, size_t len, int flags)
{
	(void)user;
	(void)buf;
	(void)len;
	(void)flags;
	return TLS_ERROR_SEND_AGAIN;
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

int main(void)
{
	TLS_CTX ctx;
	TLS_CONNECT conn;
	probe_io io = {0};
	TLS_IO callbacks = {&io, probe_send, probe_recv};
	uint8_t random[32] = {0};
	const int cipher_suite = TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256;
	size_t record_len = 0;
	int ret;

	if (tls_ctx_init(&ctx, TLS_protocol_tls13, TLS_server_mode) != 1) return 1;
	if (tls_ctx_set_protocol_range(&ctx, TLS_protocol_tls12, TLS_protocol_tls13) != 1) return 2;

	memset(&conn, 0, sizeof(conn));
	conn.ctx = &ctx;
	conn.protocol = TLS_protocol_tls13;
	conn.handshake_state = TLS_state_client_hello;
	if (tls_set_io(&conn, &callbacks) != 1) return 3;

	random[31] = 0x42;
	if (tls_record_set_protocol(io.input, TLS_protocol_tls1) != 1) return 4;
	if (tls_record_set_handshake_client_hello(
			io.input, &record_len, TLS_protocol_tls12, random,
			NULL, 0, &cipher_suite, 1, NULL, 0) != 1) return 5;
	io.input_len = record_len;

	ret = tls13_do_server_handshake(&conn);
	if (ret != 1) return 6;
	if (conn.protocol != TLS_protocol_tls12) return 7;
	if (conn.handshake_state != TLS_state_client_hello) return 8;
	if (conn.recordlen != record_len) return 9;
	if (io.input_off != io.input_len) return 10;

	puts("GmSSL TLS range server TLS 1.2 dispatch: PASS");
	tls_ctx_cleanup(&ctx);
	return 0;
}
