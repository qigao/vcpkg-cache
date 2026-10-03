# Stable read-only TLS inspection API for Salts/CNet.
# Consumers should not depend on the public TLS_CONNECT field layout.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_send_record(TLS_CONNECT *conn);
int tls_recv_record(TLS_CONNECT *conn);
]==]
[==[
int tls_send_record(TLS_CONNECT *conn);
int tls_recv_record(TLS_CONNECT *conn);

int tls_get_handshake_complete(const TLS_CONNECT *conn, int *complete);
int tls_get_negotiated_protocol(const TLS_CONNECT *conn, int *protocol);
int tls_get_negotiated_cipher_suite(const TLS_CONNECT *conn, int *cipher_suite);
int tls_get_negotiated_cipher_name(const TLS_CONNECT *conn, const char **name);
int tls_get_selected_alpn(const TLS_CONNECT *conn, const char **protocol, size_t *protocol_len);
int tls_get_peer_certificate_chain(const TLS_CONNECT *conn,
	const uint8_t **cert_chain, size_t *cert_chain_len);
int tls_get_peer_certificate(const TLS_CONNECT *conn,
	const uint8_t **cert, size_t *certlen);
int tls_get_peer_certificate_sha256(const TLS_CONNECT *conn, uint8_t digest_out[32]);
int tls_get_verify_result(const TLS_CONNECT *conn, int *result);
int tls_get_peer_close_notify(const TLS_CONNECT *conn, int *received);
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_get_verify_result(TLS_CONNECT *conn, int *result)
{
	*result = conn->verify_result;
	return 1;
}
]==]
[==[
int tls_get_handshake_complete(const TLS_CONNECT *conn, int *complete)
{
	if (!conn || !complete) {
		error_print();
		return -1;
	}
	*complete = conn->handshake_state == TLS_state_handshake_over;
	return 1;
}

int tls_get_negotiated_protocol(const TLS_CONNECT *conn, int *protocol)
{
	if (!conn || !protocol) {
		error_print();
		return -1;
	}
	if (conn->handshake_state != TLS_state_handshake_over || !conn->protocol) {
		return 0;
	}
	*protocol = conn->protocol;
	return 1;
}

int tls_get_negotiated_cipher_suite(const TLS_CONNECT *conn, int *cipher_suite)
{
	if (!conn || !cipher_suite) {
		error_print();
		return -1;
	}
	if (conn->handshake_state != TLS_state_handshake_over || !conn->cipher_suite) {
		return 0;
	}
	*cipher_suite = conn->cipher_suite;
	return 1;
}

int tls_get_negotiated_cipher_name(const TLS_CONNECT *conn, const char **name)
{
	const char *cipher_name;
	if (!conn || !name) {
		error_print();
		return -1;
	}
	if (conn->handshake_state != TLS_state_handshake_over || !conn->cipher_suite) {
		return 0;
	}
	cipher_name = tls_cipher_suite_name(conn->cipher_suite);
	if (!cipher_name) {
		error_print();
		return -1;
	}
	*name = cipher_name;
	return 1;
}

int tls_get_selected_alpn(const TLS_CONNECT *conn, const char **protocol, size_t *protocol_len)
{
	if (!conn || !protocol || !protocol_len) {
		error_print();
		return -1;
	}
	if (conn->handshake_state != TLS_state_handshake_over || !conn->alpn_selected) {
		return 0;
	}
	*protocol = conn->alpn_selected;
	*protocol_len = strlen(conn->alpn_selected);
	return 1;
}

int tls_get_peer_certificate_chain(const TLS_CONNECT *conn,
	const uint8_t **cert_chain, size_t *cert_chain_len)
{
	if (!conn || !cert_chain || !cert_chain_len) {
		error_print();
		return -1;
	}
	if (conn->handshake_state != TLS_state_handshake_over || !conn->peer_cert_chain_len) {
		return 0;
	}
	*cert_chain = conn->peer_cert_chain;
	*cert_chain_len = conn->peer_cert_chain_len;
	return 1;
}

int tls_get_peer_certificate(const TLS_CONNECT *conn,
	const uint8_t **cert, size_t *certlen)
{
	if (!conn || !cert || !certlen) {
		error_print();
		return -1;
	}
	if (conn->handshake_state != TLS_state_handshake_over || !conn->peer_cert_chain_len) {
		return 0;
	}
	if (x509_certs_get_cert_by_index(conn->peer_cert_chain, conn->peer_cert_chain_len,
		0, cert, certlen) != 1) {
		error_print();
		return -1;
	}
	return 1;
}

int tls_get_peer_certificate_sha256(const TLS_CONNECT *conn, uint8_t digest_out[32])
{
	const uint8_t *cert;
	size_t certlen;
	size_t digest_len = 0;
	int ret;

	if (!conn || !digest_out) {
		error_print();
		return -1;
	}
	ret = tls_get_peer_certificate(conn, &cert, &certlen);
	if (ret != 1) return ret;
	if (digest(DIGEST_sha256(), cert, certlen, digest_out, &digest_len) != 1
		|| digest_len != 32) {
		error_print();
		return -1;
	}
	return 1;
}

int tls_get_verify_result(const TLS_CONNECT *conn, int *result)
{
	if (!conn || !result) {
		error_print();
		return -1;
	}
	if (conn->handshake_state != TLS_state_handshake_over) {
		return 0;
	}
	*result = conn->verify_result;
	return 1;
}

int tls_get_peer_close_notify(const TLS_CONNECT *conn, int *received)
{
	if (!conn || !received) {
		error_print();
		return -1;
	}
	*received = conn->close_notify_received ? 1 : 0;
	return 1;
}
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
