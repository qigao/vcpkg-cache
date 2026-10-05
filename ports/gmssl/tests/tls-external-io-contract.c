#include <gmssl/tls.h>

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef GMSSL_EXTERNAL_IO_CA_CERT
#error GMSSL_EXTERNAL_IO_CA_CERT is required
#endif
#ifndef GMSSL_EXTERNAL_IO_SERVER_CERT
#error GMSSL_EXTERNAL_IO_SERVER_CERT is required
#endif
#ifndef GMSSL_EXTERNAL_IO_SERVER_KEY
#error GMSSL_EXTERNAL_IO_SERVER_KEY is required
#endif

#ifndef GMSSL_EXTERNAL_IO_PROTOCOL
#define GMSSL_EXTERNAL_IO_PROTOCOL TLS_protocol_tls13
#endif
#ifndef GMSSL_EXTERNAL_IO_CIPHER
#define GMSSL_EXTERNAL_IO_CIPHER TLS_cipher_aes_128_gcm_sha256
#endif
#ifndef GMSSL_EXTERNAL_IO_SIGALG
#define GMSSL_EXTERNAL_IO_SIGALG TLS_sig_rsa_pss_rsae_sha256
#endif
#ifndef GMSSL_EXTERNAL_IO_LABEL
#define GMSSL_EXTERNAL_IO_LABEL "TLS"
#endif

#define PIPE_CAPACITY 1024u
#define SEND_LIMIT 73u
#define RECV_LIMIT 41u
#define DRIVE_LIMIT 200000u

typedef struct fixed_pipe {
	uint8_t data[PIPE_CAPACITY];
	size_t length;
	size_t peak;
} fixed_pipe;

typedef struct memory_io {
	fixed_pipe *tx;
	fixed_pipe *rx;
	int force_send_again;
	int force_recv_again;
	size_t send_calls;
	size_t recv_calls;
	size_t send_again;
	size_t recv_again;
	size_t short_send;
	size_t short_recv;
} memory_io;

static size_t min_size(size_t a, size_t b)
{
	return a < b ? a : b;
}

static tls_ret_t memory_send(void *user, const void *buf, size_t len, int flags)
{
	memory_io *io = (memory_io *)user;
	size_t available;
	size_t count;
	(void)flags;

	if (!io || !io->tx || !buf || !len) return TLS_ERROR_SYSCALL;
	++io->send_calls;
	if (io->force_send_again) {
		io->force_send_again = 0;
		++io->send_again;
		return TLS_ERROR_SEND_AGAIN;
	}
	available = PIPE_CAPACITY - io->tx->length;
	if (!available) {
		++io->send_again;
		return TLS_ERROR_SEND_AGAIN;
	}
	count = min_size(len, min_size(available, SEND_LIMIT));
	memcpy(io->tx->data + io->tx->length, buf, count);
	io->tx->length += count;
	if (io->tx->peak < io->tx->length) io->tx->peak = io->tx->length;
	if (count < len) ++io->short_send;
	return (tls_ret_t)count;
}

static tls_ret_t memory_recv(void *user, void *buf, size_t len, int flags)
{
	memory_io *io = (memory_io *)user;
	size_t count;
	(void)flags;

	if (!io || !io->rx || !buf || !len) return TLS_ERROR_SYSCALL;
	++io->recv_calls;
	if (io->force_recv_again) {
		io->force_recv_again = 0;
		++io->recv_again;
		return TLS_ERROR_RECV_AGAIN;
	}
	if (!io->rx->length) {
		++io->recv_again;
		return TLS_ERROR_RECV_AGAIN;
	}
	count = min_size(len, min_size(io->rx->length, RECV_LIMIT));
	memcpy(buf, io->rx->data, count);
	io->rx->length -= count;
	if (io->rx->length)
		memmove(io->rx->data, io->rx->data + count, io->rx->length);
	if (count < len) ++io->short_recv;
	return (tls_ret_t)count;
}

static int retryable(int ret)
{
	return ret == TLS_ERROR_SEND_AGAIN || ret == TLS_ERROR_RECV_AGAIN;
}

static int handshake_complete(TLS_CONNECT *conn)
{
	int complete = 0;
	if (tls_get_handshake_complete(conn, &complete) != 1) return -1;
	return complete;
}

static int drive_handshake(TLS_CONNECT *client, TLS_CONNECT *server)
{
	size_t iteration;
	for (iteration = 0; iteration < DRIVE_LIMIT; ++iteration) {
		int client_complete = handshake_complete(client);
		int server_complete = handshake_complete(server);
		int ret;
		if (client_complete < 0 || server_complete < 0) return -1;
		if (client_complete && server_complete) return 1;

		if (!client_complete) {
			ret = tls_do_handshake(client);
			if (ret != 1 && !retryable(ret)) return -2;
		}
		if (!server_complete) {
			ret = tls_do_handshake(server);
			if (ret != 1 && !retryable(ret)) return -3;
		}
	}
	return -4;
}

static int drive_application_data(TLS_CONNECT *client, TLS_CONNECT *server)
{
	uint8_t sent[3072];
	uint8_t received[sizeof(sent)];
	size_t received_len = 0;
	int send_done = 0;
	size_t iteration;

	for (size_t i = 0; i < sizeof(sent); ++i)
		sent[i] = (uint8_t)(i * 17u + 3u);
	memset(received, 0, sizeof(received));

	for (iteration = 0; iteration < DRIVE_LIMIT; ++iteration) {
		if (!send_done) {
			size_t sent_len = 0;
			int ret = tls_send(client, sent, sizeof(sent), &sent_len);
			if (ret == 1) {
				if (sent_len != sizeof(sent)) return -1;
				send_done = 1;
			} else if (!retryable(ret)) {
				return -2;
			}
		}

		if (received_len < sizeof(received)) {
			size_t chunk = 0;
			int ret = tls_recv(server, received + received_len,
				sizeof(received) - received_len, &chunk);
			if (ret == 1) {
				if (!chunk || chunk > sizeof(received) - received_len) return -3;
				received_len += chunk;
			} else if (!retryable(ret)) {
				return -4;
			}
		}

		if (send_done && received_len == sizeof(received)) {
			return memcmp(sent, received, sizeof(sent)) == 0 ? 1 : -5;
		}
	}
	return -6;
}

static int drive_shutdown(TLS_CONNECT *client, TLS_CONNECT *server)
{
	int client_done = 0;
	int server_done = 0;
	size_t iteration;

	for (iteration = 0; iteration < DRIVE_LIMIT; ++iteration) {
		int ret;
		if (!client_done) {
			ret = tls_shutdown(client);
			if (ret == 1) client_done = 1;
			else if (!retryable(ret)) return -1;
		}
		if (!server_done) {
			ret = tls_shutdown(server);
			if (ret == 1) server_done = 1;
			else if (!retryable(ret)) return -2;
		}
		if (client_done && server_done) return 1;
	}
	return -3;
}

int main(int argc, char **argv)
{
	enum { INVALID_ARGUMENTS = 17, INVALID_SNI_STATE = 18 };
	const int send_sni = argc == 1;
	TLS_CTX client_ctx;
	TLS_CTX server_ctx;
	TLS_CONNECT client;
	TLS_CONNECT server;
	fixed_pipe client_to_server = {{0}, 0u, 0u};
	fixed_pipe server_to_client = {{0}, 0u, 0u};
	memory_io client_io = {
		&client_to_server, &server_to_client, 1, 1,
		0u, 0u, 0u, 0u, 0u, 0u};
	memory_io server_io = {
		&server_to_client, &client_to_server, 1, 1,
		0u, 0u, 0u, 0u, 0u, 0u};
	TLS_IO client_callbacks = {&client_io, memory_send, memory_recv};
	TLS_IO server_callbacks = {&server_io, memory_send, memory_recv};
	const int cipher_suite = GMSSL_EXTERNAL_IO_CIPHER;
	const int group = TLS_curve_secp256r1;
	const int sig_algs[] = {
		GMSSL_EXTERNAL_IO_SIGALG,
		TLS_sig_rsa_pkcs1_sha256,
	};
	const size_t sig_algs_cnt =
		GMSSL_EXTERNAL_IO_PROTOCOL == TLS_protocol_tls13 ? 2u : 1u;
	int client_ctx_ready = 0;
	int server_ctx_ready = 0;
	int client_ready = 0;
	int server_ready = 0;
	int client_close = 0;
	int server_close = 0;
	int rc = 1;
	if (!send_sni && (argc != 2 || strcmp(argv[1], "--no-sni") != 0)) {
		fprintf(stderr, "usage: %s [--no-sni]\n", argv[0]);
		return INVALID_ARGUMENTS;
	}

	memset(&client_ctx, 0, sizeof(client_ctx));
	memset(&server_ctx, 0, sizeof(server_ctx));
	memset(&client, 0, sizeof(client));
	memset(&server, 0, sizeof(server));

	if (tls_ctx_init(&client_ctx, GMSSL_EXTERNAL_IO_PROTOCOL, TLS_client_mode) != 1) {
		rc = 2; goto cleanup;
	}
	client_ctx_ready = 1;
	if (tls_ctx_set_cipher_suites(&client_ctx, &cipher_suite, 1u) != 1
		|| tls_ctx_set_supported_groups(&client_ctx, &group, 1u) != 1
		|| tls_ctx_set_signature_algorithms(&client_ctx, sig_algs, sig_algs_cnt) != 1
		|| tls_ctx_set_ca_certificates(&client_ctx, GMSSL_EXTERNAL_IO_CA_CERT, 4) != 1) {
		rc = 3; goto cleanup;
	}

	if (tls_ctx_init(&server_ctx, GMSSL_EXTERNAL_IO_PROTOCOL, TLS_server_mode) != 1) {
		rc = 4; goto cleanup;
	}
	server_ctx_ready = 1;
	if (tls_ctx_set_cipher_suites(&server_ctx, &cipher_suite, 1u) != 1
		|| tls_ctx_set_supported_groups(&server_ctx, &group, 1u) != 1
		|| tls_ctx_set_signature_algorithms(&server_ctx, sig_algs, sig_algs_cnt) != 1
		|| tls_ctx_set_certificate_and_key(
			&server_ctx,
			GMSSL_EXTERNAL_IO_SERVER_CERT,
			GMSSL_EXTERNAL_IO_SERVER_KEY,
			"") != 1) {
		rc = 5; goto cleanup;
	}

	if (tls_init(&client, &client_ctx) != 1) {
		rc = 6; goto cleanup;
	}
	client_ready = 1;
	if (tls_set_hostname(&client, "localhost") != 1
		|| (send_sni && tls_set_server_name(&client) != 1)
		|| tls_set_io(&client, &client_callbacks) != 1
		|| tls_socket_is_valid(client.sock)) {
		rc = 7; goto cleanup;
	}

	if (tls_init(&server, &server_ctx) != 1) {
		rc = 8; goto cleanup;
	}
	server_ready = 1;
	if (tls_set_io(&server, &server_callbacks) != 1
		|| tls_socket_is_valid(server.sock)) {
		rc = 9; goto cleanup;
	}

	if (drive_handshake(&client, &server) != 1) {
		rc = 10; goto cleanup;
	}
	if (client.protocol != GMSSL_EXTERNAL_IO_PROTOCOL || server.protocol != GMSSL_EXTERNAL_IO_PROTOCOL) {
		rc = 11; goto cleanup;
	}
	if (client.server_name != send_sni || server.server_name != send_sni) {
		rc = INVALID_SNI_STATE; goto cleanup;
	}

	client_io.force_send_again = 1;
	server_io.force_recv_again = 1;
	if (drive_application_data(&client, &server) != 1) {
		rc = 12; goto cleanup;
	}

	client_io.force_send_again = 1;
	client_io.force_recv_again = 1;
	server_io.force_send_again = 1;
	server_io.force_recv_again = 1;
	if (drive_shutdown(&client, &server) != 1) {
		rc = 13; goto cleanup;
	}
	if (tls_get_peer_close_notify(&client, &client_close) != 1 || !client_close
		|| tls_get_peer_close_notify(&server, &server_close) != 1 || !server_close) {
		rc = 14; goto cleanup;
	}

	if (!client_io.send_again || !client_io.recv_again
		|| !server_io.send_again || !server_io.recv_again
		|| !client_io.short_send || !client_io.short_recv
		|| !server_io.short_send || !server_io.short_recv) {
		rc = 15; goto cleanup;
	}
	if (client_to_server.peak > PIPE_CAPACITY || server_to_client.peak > PIPE_CAPACITY
		|| client_to_server.length != 0u || server_to_client.length != 0u) {
		rc = 16; goto cleanup;
	}

	printf("GmSSL callback-only %s contract: PASS "
		"(SNI=%s, c->s peak=%zu, s->c peak=%zu, short-send=%zu/%zu, short-recv=%zu/%zu)\n",
		GMSSL_EXTERNAL_IO_LABEL,
		send_sni ? "present" : "absent",
		client_to_server.peak, server_to_client.peak,
		client_io.short_send, server_io.short_send,
		client_io.short_recv, server_io.short_recv);
	rc = 0;

cleanup:
	if (server_ready) tls_cleanup(&server);
	if (client_ready) tls_cleanup(&client);
	if (server_ctx_ready) tls_ctx_cleanup(&server_ctx);
	if (client_ctx_ready) tls_ctx_cleanup(&client_ctx);
	return rc;
}
