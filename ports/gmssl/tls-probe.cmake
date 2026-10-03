# Non-consuming TLS control probe for event-driven transports.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_recv(TLS_CONNECT *conn, uint8_t *out, size_t outlen, size_t *recvlen);
int tls_shutdown(TLS_CONNECT *conn);
]==]
[==[
int tls_recv(TLS_CONNECT *conn, uint8_t *out, size_t outlen, size_t *recvlen);
int tls_probe(TLS_CONNECT *conn, int *peer_closed, int *plaintext_pending);
int tls_shutdown(TLS_CONNECT *conn);
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_recv(TLS_CONNECT *conn, uint8_t *out, size_t outlen, size_t *recvlen)
{
]==]
[==[
extern int tls13_do_recv(TLS_CONNECT *conn);

int tls_probe(TLS_CONNECT *conn, int *peer_closed, int *plaintext_pending)
{
	int ret;

	if (!conn || !peer_closed || !plaintext_pending) {
		error_print();
		return -1;
	}
	*peer_closed = conn->close_notify_received ? 1 : 0;
	*plaintext_pending = conn->datalen ? 1 : 0;
	if (*peer_closed || *plaintext_pending) {
		return 1;
	}
	if (conn->handshake_state != TLS_state_handshake_over) {
		return 1;
	}

	switch (conn->protocol) {
	case TLS_protocol_tlcp:
	case TLS_protocol_tls12:
		ret = tls_decrypt_recv(conn);
		if (ret != 1) {
			if (ret == TLS_ERROR_TCP_CLOSED) {
				*peer_closed = 1;
				return 1;
			}
			return ret;
		}
		switch (tls_record_type(conn->record)) {
		case TLS_record_application_data:
			tls_clean_record(conn);
			*plaintext_pending = conn->datalen ? 1 : 0;
			return 1;
		case TLS_record_alert: {
			int level;
			int alert;
			if (tls_record_get_alert(conn->databuf, &level, &alert) != 1) {
				error_print();
				return -1;
			}
			conn->data = NULL;
			conn->datalen = 0;
			tls_clean_record(conn);
			if (alert == TLS_alert_close_notify) {
				conn->close_notify_received = 1;
				*peer_closed = 1;
				return 1;
			}
			return -1;
		}
		default:
			tls_clean_record(conn);
			error_print();
			return -1;
		}

	case TLS_protocol_tls13:
		for (;;) {
			ret = tls13_do_recv(conn);
			if (ret == 0) {
				*peer_closed = conn->close_notify_received ? 1 : 0;
				return 1;
			}
			if (ret != 1) {
				if (ret == TLS_ERROR_TCP_CLOSED) {
					*peer_closed = 1;
					return 1;
				}
				return ret;
			}
			if (conn->datalen) {
				*plaintext_pending = 1;
				return 1;
			}
			conn->record_offset = 0;
			conn->recordlen = 0;
			conn->plain_recordlen = 0;
		}

	default:
		error_print();
		return -1;
	}
}

int tls_recv(TLS_CONNECT *conn, uint8_t *out, size_t outlen, size_t *recvlen)
{
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
