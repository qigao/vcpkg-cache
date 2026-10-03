# Borrowed ALPN list storage bounded by the protocol's uint16 wire length.
# The embedding context owns the pointer list and strings for the TLS_CTX lifetime.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

vcpkg_replace_string(
    "${_gmssl_tls_h}"
    "	char *alpn_protocols[4];"
    "	char **alpn_protocols;"
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_ctx_set_application_layer_protocol_negotiation(TLS_CTX *ctx,
	char *protocols[], size_t protocols_cnt)
{
	size_t i;

	if (!ctx || !protocols || !protocols_cnt) {
		error_print();
		return -1;
	}
	if (protocols_cnt > sizeof(ctx->alpn_protocols)/sizeof(ctx->alpn_protocols[0])) {
		error_print();
		return -1;
	}
	for (i = 0; i < protocols_cnt; i++) {
		size_t protocol_len;

		if (!protocols[i]) {
			error_print();
			return -1;
		}
		protocol_len = strlen(protocols[i]);
		if (protocol_len < 1 || protocol_len > 255) {
			error_print();
			return -1;
		}
		ctx->alpn_protocols[i] = protocols[i];
	}
	ctx->alpn_protocols_cnt = protocols_cnt;
	ctx->application_layer_protocol_negotiation = 1;

	return 1;
}
]==]
[==[
int tls_ctx_set_application_layer_protocol_negotiation(TLS_CTX *ctx,
	char *protocols[], size_t protocols_cnt)
{
	enum { TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE = 65535 };
	size_t i;
	size_t wire_len = 0;

	if (!ctx || !protocols || !protocols_cnt) {
		error_print();
		return -1;
	}
	for (i = 0; i < protocols_cnt; i++) {
		size_t protocol_len;

		if (!protocols[i]) {
			error_print();
			return -1;
		}
		protocol_len = strlen(protocols[i]);
		if (protocol_len < 1 || protocol_len > 255
			|| wire_len > TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE - 1 - protocol_len) {
			error_print();
			return -1;
		}
		wire_len += 1 + protocol_len;
	}
	ctx->alpn_protocols = protocols;
	ctx->alpn_protocols_cnt = protocols_cnt;
	ctx->application_layer_protocol_negotiation = 1;

	return 1;
}
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
