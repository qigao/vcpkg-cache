# Backport the upstream TLS connection cleanup fix for the pinned GmSSL source.
# tls_client_verify_update() owns heap transcript copies; they must be released
# before TLS_CONNECT is securely cleared.

set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
void tls_cleanup(TLS_CONNECT *conn)
{
	gmssl_secure_clear(conn, sizeof(TLS_CONNECT));
}
]==]
[==[
void tls_cleanup(TLS_CONNECT *conn)
{
	if (!conn) {
		return;
	}
	tls_client_verify_cleanup(&conn->client_verify_ctx);
	gmssl_secure_clear(conn, sizeof(TLS_CONNECT));
}
]==]
)

unset(_gmssl_tls_c)
