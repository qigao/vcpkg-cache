# External platform-trust seam for consumers that cannot enumerate native roots
# (notably iOS Security.framework). This skips only GmSSL's trust-anchor path
# verification; certificate matching, hostname checks and CertificateVerify stay
# inside GmSSL.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_cert_c "${SOURCE_PATH}/src/tls_cert.c")
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
	int external_trust;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
]==]
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
int tls_ctx_enable_external_trust(TLS_CTX *ctx, int enable);
]==]
)

# File-backed CA trust and external trust are mutually exclusive.
gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
	if (ctx->cacerts) {
]==]
[==[
	if (ctx->cacerts || ctx->external_trust) {
]==]
)

# The DER trust-store adaptation is injected by trust-anchors.cmake earlier.
gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
		|| !tls_protocol_name(ctx->protocol)
		|| ctx->cacerts) {
]==]
[==[
		|| !tls_protocol_name(ctx->protocol)
		|| ctx->cacerts || ctx->external_trust) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
int tls_authorities_from_certs(uint8_t *names, size_t *nameslen, size_t maxlen, const uint8_t *certs, size_t certslen)
]==]
[==[
int tls_ctx_enable_external_trust(TLS_CTX *ctx, int enable)
{
	if (!ctx || !ctx->is_client || (enable != 0 && enable != 1)) {
		error_print();
		return -1;
	}
	if (enable && ctx->cacerts) {
		error_print();
		return -1;
	}
	ctx->external_trust = enable;
	return 1;
}

int tls_authorities_from_certs(uint8_t *names, size_t *nameslen, size_t maxlen, const uint8_t *certs, size_t certslen)
]==]
)

# TLS 1.2 already makes chain verification conditional on CA presence. External
# trust must explicitly override that path while retaining tls_cert_chain_match.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		conn->ctx->cacertslen ? 1 : 0,
		conn->peer_cert_chain, conn->peer_cert_chain_len,
]==]
[==[
		conn->ctx->external_trust ? 0 : (conn->ctx->cacertslen ? 1 : 0),
		conn->peer_cert_chain, conn->peer_cert_chain_len,
]==]
)

# TLS 1.3 hard-codes verify_chain=1 upstream. Keep that default, but allow the
# explicit client-only external-trust seam to defer only the root/path decision.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	ret = tls_cert_chain_verify(
		conn->protocol, X509_cert_chain_server, conn->cipher_suite,
		1,
		conn->peer_cert_chain, conn->peer_cert_chain_len,
]==]
[==[
	ret = tls_cert_chain_verify(
		conn->protocol, X509_cert_chain_server, conn->cipher_suite,
		conn->ctx->external_trust ? 0 : 1,
		conn->peer_cert_chain, conn->peer_cert_chain_len,
]==]
)

# Build-time postconditions keep the seam narrow and fail if upstream shifts.
file(READ "${_gmssl_tls_h}" _gmssl_external_trust_h)
file(READ "${_gmssl_tls12_c}" _gmssl_external_trust_tls12)
file(READ "${_gmssl_tls13_c}" _gmssl_external_trust_tls13)
foreach(_needle
    "int tls_ctx_enable_external_trust(TLS_CTX *ctx, int enable);"
    "int external_trust;")
    string(FIND "${_gmssl_external_trust_h}" "${_needle}" _offset)
    if(_offset EQUAL -1)
        message(FATAL_ERROR "GmSSL external-trust header contract missing: ${_needle}")
    endif()
endforeach()
string(FIND "${_gmssl_external_trust_tls12}"
    "conn->ctx->external_trust ? 0 : (conn->ctx->cacertslen ? 1 : 0)"
    _gmssl_external_trust_tls12_offset)
if(_gmssl_external_trust_tls12_offset EQUAL -1)
    message(FATAL_ERROR "GmSSL TLS 1.2 external-trust contract missing")
endif()
string(FIND "${_gmssl_external_trust_tls13}"
    "conn->ctx->external_trust ? 0 : 1"
    _gmssl_external_trust_tls13_offset)
if(_gmssl_external_trust_tls13_offset EQUAL -1)
    message(FATAL_ERROR "GmSSL TLS 1.3 external-trust contract missing")
endif()

unset(_gmssl_external_trust_tls13_offset)
unset(_gmssl_external_trust_tls12_offset)
unset(_gmssl_external_trust_tls13)
unset(_gmssl_external_trust_tls12)
unset(_gmssl_external_trust_h)
unset(_gmssl_tls13_c)
unset(_gmssl_tls12_c)
unset(_gmssl_tls_cert_c)
unset(_gmssl_tls_h)
