#include <gmssl/tls.h>

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct probe_io {
	size_t recv_calls;
} probe_io;

static tls_ret_t probe_send(void *user, const void *buf, size_t len, int flags)
{
	(void)user; (void)buf; (void)len; (void)flags;
	return TLS_ERROR_SEND_AGAIN;
}

static tls_ret_t probe_recv(void *user, void *buf, size_t len, int flags)
{
	probe_io *io = (probe_io *)user;
	(void)buf; (void)len; (void)flags;
	if (!io) return TLS_ERROR_SYSCALL;
	io->recv_calls++;
	return TLS_ERROR_RECV_AGAIN;
}

static int check_protocol(int protocol)
{
	TLS_CONNECT conn;
	TLS_IO callbacks;
	probe_io io = {0};
	int closed = -1;
	int pending = -1;

	memset(&conn, 0, sizeof(conn));
	callbacks.user = &io;
	callbacks.send = probe_send;
	callbacks.recv = probe_recv;
	conn.protocol = protocol;
	conn.handshake_state = TLS_state_handshake_over;
	if (tls_set_io(&conn, &callbacks) != 1) return 1;
	if (tls_probe(&conn, &closed, &pending) != TLS_ERROR_RECV_AGAIN) return 2;
	if (io.recv_calls != 1 || closed != 0 || pending != 0) return 3;
	return 0;
}

int main(void)
{
	TLS_CONNECT conn;
	TLS_IO callbacks;
	probe_io io = {0};
	uint8_t plaintext[] = {0x11, 0x22, 0x33};
	int closed = -1;
	int pending = -1;

	memset(&conn, 0, sizeof(conn));
	callbacks.user = &io;
	callbacks.send = probe_send;
	callbacks.recv = probe_recv;
	conn.protocol = TLS_protocol_tls13;
	conn.handshake_state = TLS_state_handshake_over;
	conn.data = plaintext;
	conn.datalen = sizeof(plaintext);
	if (tls_set_io(&conn, &callbacks) != 1) return 1;
	if (tls_probe(&conn, &closed, &pending) != 1) return 2;
	if (closed != 0 || pending != 1 || io.recv_calls != 0) return 3;
	if (conn.data != plaintext || conn.datalen != sizeof(plaintext)) return 4;

	conn.data = NULL;
	conn.datalen = 0;
	conn.close_notify_received = 1;
	if (tls_probe(&conn, &closed, &pending) != 1) return 5;
	if (closed != 1 || pending != 0 || io.recv_calls != 0) return 6;

	if (check_protocol(TLS_protocol_tls12) != 0) return 7;
	if (check_protocol(TLS_protocol_tls13) != 0) return 8;

	puts("GmSSL non-consuming TLS probe contract: PASS");
	return 0;
}
