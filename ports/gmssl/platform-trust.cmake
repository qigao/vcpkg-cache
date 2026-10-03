# External platform trust policy for embedders such as CNet on iOS.
# This skips only CA path-building; TLS certificate/signature/name/extension
# checks remain inside GmSSL.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")
set(_gmssl_tls12_c "${SOURCE_PATH}/src/tls12.c")
set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
	uint8_t *cacerts;
	size_t cacertslen;
	int verify_depth;
]==]
[==[
	uint8_t *cacerts;
	size_t cacertslen;
	int verify_depth;
	int external_peer_trust;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
]==]
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
int tls_ctx_set_external_peer_trust(TLS_CTX *ctx, int enable);
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
void tls_ctx_cleanup(TLS_CTX *ctx)
{
]==]
[==[
int tls_ctx_set_external_peer_trust(TLS_CTX *ctx, int enable)
{
	if (!ctx || !ctx->is_client) {
		error_print();
		return -1;
	}
	ctx->external_peer_trust = enable ? 1 : 0;
	return 1;
}

void tls_ctx_cleanup(TLS_CTX *ctx)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if (tls_cert_chain_verify(conn->protocol, X509_cert_chain_server, conn->cipher_suite,
		conn->ctx->cacertslen ? 1 : 0,
]==]
[==[
	if (tls_cert_chain_verify(conn->protocol, X509_cert_chain_server, conn->cipher_suite,
		conn->ctx->external_peer_trust ? 0 : (conn->ctx->cacertslen ? 1 : 0),
]==]
)

gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	ret = tls_cert_chain_verify(
		conn->protocol, X509_cert_chain_server, conn->cipher_suite,
		1,
]==]
[==[
	ret = tls_cert_chain_verify(
		conn->protocol, X509_cert_chain_server, conn->cipher_suite,
		conn->ctx->external_peer_trust ? 0 : 1,
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
unset(_gmssl_tls12_c)
unset(_gmssl_tls13_c)
