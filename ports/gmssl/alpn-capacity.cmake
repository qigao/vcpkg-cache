# Borrowed ALPN list storage bounded by the protocol's uint16 wire length.
# The embedding context owns the pointer list and strings for the TLS_CTX lifetime.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")
set(_gmssl_tls_alpn_c "${SOURCE_PATH}/src/tls_alpn.c")

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

# Keep tls_ctx_check() aligned with the borrowed-list setter. Revalidate the
# same protocol wire bound; never use sizeof(pointer) as a count limit.
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	if (ctx->application_layer_protocol_negotiation && !ctx->alpn_protocols_cnt) {
		error_print();
		return -1;
	}
	if (!ctx->application_layer_protocol_negotiation && ctx->alpn_protocols_cnt) {
		error_print();
		return -1;
	}
	if (ctx->alpn_protocols_cnt > sizeof(ctx->alpn_protocols)/sizeof(ctx->alpn_protocols[0])) {
		error_print();
		return -1;
	}
	for (i = 0; i < ctx->alpn_protocols_cnt; i++) {
		size_t protocol_len;

		if (!ctx->alpn_protocols[i]) {
			error_print();
			return -1;
		}
		protocol_len = strlen(ctx->alpn_protocols[i]);
		if (protocol_len < 1 || protocol_len > 255) {
			error_print();
			return -1;
		}
	}
]==]
[==[
	if (ctx->application_layer_protocol_negotiation
		&& (!ctx->alpn_protocols || !ctx->alpn_protocols_cnt)) {
		error_print();
		return -1;
	}
	if (!ctx->application_layer_protocol_negotiation
		&& (ctx->alpn_protocols || ctx->alpn_protocols_cnt)) {
		error_print();
		return -1;
	}
	if (ctx->alpn_protocols_cnt) {
		enum { TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE = 65535 };
		size_t wire_len = 0;
		for (i = 0; i < ctx->alpn_protocols_cnt; i++) {
			size_t protocol_len;
			if (!ctx->alpn_protocols[i]) {
				error_print();
				return -1;
			}
			protocol_len = strlen(ctx->alpn_protocols[i]);
			if (protocol_len < 1 || protocol_len > 255
				|| wire_len > TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE - 1 - protocol_len) {
				error_print();
				return -1;
			}
			wire_len += 1 + protocol_len;
		}
	}
]==]
)


# The serializer must enforce the protocol wire bound, not a TLS_CTX storage count.
gmssl_replace_once(
    "${_gmssl_tls_alpn_c}"
[==[
#define tls_application_layer_protocol_negotiation_max_count() \
	(sizeof(((TLS_CTX *)0)->alpn_protocols) \
		/ sizeof(((TLS_CTX *)0)->alpn_protocols[0]))


]==]
[==[
#define TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE 65535


]==]
)

gmssl_replace_once(
    "${_gmssl_tls_alpn_c}"
[==[
	if (!protocols || !protocols_cnt
		|| protocols_cnt > tls_application_layer_protocol_negotiation_max_count()
		|| !outlen) {
]==]
[==[
	if (!protocols || !protocols_cnt || !outlen) {
]==]
)


# tls_ctx_check() must validate the same borrowed-list wire bound as the setter.
vcpkg_replace_string(
    "${_gmssl_tls_c}"
[==[
	if (ctx->alpn_protocols_cnt > sizeof(ctx->alpn_protocols)/sizeof(ctx->alpn_protocols[0])) {
		error_print();
		return -1;
	}
]==]
[==[
	size_t alpn_wire_len = 0;
]==]
)

vcpkg_replace_string(
    "${_gmssl_tls_c}"
[==[
		protocol_len = strlen(ctx->alpn_protocols[i]);
		if (protocol_len < 1 || protocol_len > 255) {
			error_print();
			return -1;
		}
]==]
[==[
		protocol_len = strlen(ctx->alpn_protocols[i]);
		if (protocol_len < 1 || protocol_len > 255
			|| alpn_wire_len > 65535 - 1 - protocol_len) {
			error_print();
			return -1;
		}
		alpn_wire_len += 1 + protocol_len;
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
unset(_gmssl_tls_alpn_c)
