# Single-connection standard TLS 1.2-1.3 client negotiation.
#
# The client starts with one TLS 1.3-compatible ClientHello containing
# supported_versions {1.3,1.2} and a union of configured TLS 1.3/TLS 1.2
# cipher suites. A normal ServerHello is retained by the existing HRR state.
# At ServerHello, the same record is inspected and the connection dispatches
# to TLS 1.3 or TLS 1.2 without reconnecting or rereading transport bytes.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")
set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
	int protocol;


	int cipher_suites[TLS_MAX_CIPHER_SUITES];
]==]
[==[
	int protocol;
	int min_protocol;
	int max_protocol;


	int cipher_suites[TLS_MAX_CIPHER_SUITES];
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client);
int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt);
]==]
[==[
int tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client);
int tls_ctx_set_protocol_range(TLS_CTX *ctx, int min_protocol, int max_protocol);
int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt);
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	ctx->is_client = is_client ? 1 : 0;
]==]
[==[
	ctx->min_protocol = protocol;
	ctx->max_protocol = protocol;
	ctx->is_client = is_client ? 1 : 0;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
void tls_ctx_cleanup(TLS_CTX *ctx)
]==]
[==[
int tls_ctx_set_protocol_range(TLS_CTX *ctx, int min_protocol, int max_protocol)
{
	if (!ctx
		|| min_protocol != TLS_protocol_tls12
		|| max_protocol != TLS_protocol_tls13) {
		error_print();
		return -1;
	}
	ctx->protocol = TLS_protocol_tls13;
	ctx->min_protocol = min_protocol;
	ctx->max_protocol = max_protocol;
	ctx->supported_versions[0] = TLS_protocol_tls13;
	ctx->supported_versions[1] = TLS_protocol_tls12;
	ctx->supported_versions_cnt = 2;
	return 1;
}

void tls_ctx_cleanup(TLS_CTX *ctx)
]==]
)

# In range mode accept a caller-ordered union of TLS 1.3 and TLS 1.2 suites.
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	if (cipher_suites_cnt > sizeof(ctx->cipher_suites)/sizeof(ctx->cipher_suites[0])) {
		error_print();
		return -1;
	}

	switch (ctx->protocol) {
]==]
[==[
	if (cipher_suites_cnt > sizeof(ctx->cipher_suites)/sizeof(ctx->cipher_suites[0])) {
		error_print();
		return -1;
	}
	if (ctx->min_protocol == TLS_protocol_tls12
		&& ctx->max_protocol == TLS_protocol_tls13) {
		for (i = 0; i < cipher_suites_cnt; i++) {
			if (!tls_type_is_in_list(cipher_suites[i], tls13_cipher_suites, tls13_cipher_suites_cnt)
				&& !tls_type_is_in_list(cipher_suites[i], tls12_cipher_suites, tls12_cipher_suites_cnt)) {
				error_print();
				return -1;
			}
		}
		memcpy(ctx->cipher_suites, cipher_suites, cipher_suites_cnt * sizeof(cipher_suites[0]));
		ctx->cipher_suites_cnt = cipher_suites_cnt;
		return 1;
	}

	switch (ctx->protocol) {
]==]
)

# tls_ctx_check validates the same union and rejects TLS 1.3-only PSK/early
# data semantics in a version-range connection.
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	size_t cert_chains_cnt = 0;
	size_t i;

	if (!ctx) {
]==]
[==[
	size_t cert_chains_cnt = 0;
	size_t i;
	int standard_tls_range;

	if (!ctx) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	if (!ctx) {
		error_print();
		return -1;
	}

	switch (ctx->protocol) {
]==]
[==[
	if (!ctx) {
		error_print();
		return -1;
	}
	standard_tls_range =
		ctx->min_protocol == TLS_protocol_tls12
		&& ctx->max_protocol == TLS_protocol_tls13;
	if (ctx->min_protocol > ctx->max_protocol
		|| (standard_tls_range && ctx->protocol != TLS_protocol_tls13)) {
		error_print();
		return -1;
	}

	switch (ctx->protocol) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	for (i = 0; i < ctx->cipher_suites_cnt; i++) {
		if (!tls_type_is_in_list(ctx->cipher_suites[i],
			supported_cipher_suites, supported_cipher_suites_cnt)) {
			error_print();
			return -1;
		}
	}
]==]
[==[
	for (i = 0; i < ctx->cipher_suites_cnt; i++) {
		if (standard_tls_range) {
			if (!tls_type_is_in_list(ctx->cipher_suites[i], tls13_cipher_suites, tls13_cipher_suites_cnt)
				&& !tls_type_is_in_list(ctx->cipher_suites[i], tls12_cipher_suites, tls12_cipher_suites_cnt)) {
				error_print();
				return -1;
			}
		} else if (!tls_type_is_in_list(ctx->cipher_suites[i],
			supported_cipher_suites, supported_cipher_suites_cnt)) {
			error_print();
			return -1;
		}
	}
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	if (ctx->is_client && ctx->certificate_request) {
]==]
[==[
	if (standard_tls_range && (ctx->psk_key_exchange_modes || ctx->early_data)) {
		error_print();
		return -1;
	}
	if (ctx->is_client && ctx->certificate_request) {
]==]
)

# Server-side range dispatch peeks one ClientHello and keeps the same record
# buffered for the selected TLS 1.2 or TLS 1.3 state machine.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
int tls13_do_server_handshake(TLS_CONNECT *conn)
]==]
[==[
int tls12_server_handshake(TLS_CONNECT *conn);

int tls13_do_server_handshake(TLS_CONNECT *conn)
]==]
)

gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
int tls13_do_server_handshake(TLS_CONNECT *conn)
]==]
[==[
static int tls_server_client_hello_protocol(TLS_CONNECT *conn, int *selected_protocol)
{
	int ret;
	int legacy_version;
	const uint8_t *random;
	const uint8_t *legacy_session_id;
	size_t legacy_session_id_len;
	const uint8_t *cipher_suites;
	size_t cipher_suites_len;
	const uint8_t *exts;
	size_t extslen;
	const uint8_t *supported_versions = NULL;
	size_t supported_versions_len = 0;
	int common_versions[4];
	size_t common_versions_cnt = 0;

	if (!conn || !selected_protocol) {
		error_print();
		return -1;
	}
	if ((ret = tls_recv_record(conn)) != 1) {
		return ret;
	}
	if ((tls_record_protocol(conn->record) != TLS_protocol_tls1
			&& tls_record_protocol(conn->record) != TLS_protocol_tls12)
		|| tls_record_get_handshake_client_hello(conn->record,
			&legacy_version, &random,
			&legacy_session_id, &legacy_session_id_len,
			&cipher_suites, &cipher_suites_len,
			&exts, &extslen) != 1) {
		error_print();
		return -1;
	}
	while (extslen) {
		int ext_type;
		const uint8_t *ext_data;
		size_t ext_datalen;
		if (tls_ext_from_bytes(&ext_type, &ext_data, &ext_datalen, &exts, &extslen) != 1) {
			error_print();
			return -1;
		}
		if (ext_type == TLS_extension_supported_versions) {
			if (supported_versions || !ext_data) {
				error_print();
				return -1;
			}
			supported_versions = ext_data;
			supported_versions_len = ext_datalen;
		}
	}
	if (!supported_versions) {
		if (legacy_version != TLS_protocol_tls12) {
			error_print();
			return -1;
		}
		*selected_protocol = TLS_protocol_tls12;
		return 1;
	}
	ret = tls13_process_client_supported_versions(
		supported_versions, supported_versions_len,
		conn->ctx->supported_versions, conn->ctx->supported_versions_cnt,
		common_versions, &common_versions_cnt,
		sizeof(common_versions)/sizeof(common_versions[0]));
	if (ret != 1 || common_versions_cnt == 0) {
		return ret;
	}
	*selected_protocol = common_versions[0];
	return 1;
}

int tls13_do_server_handshake(TLS_CONNECT *conn)
]==]
)

gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	case TLS_state_client_hello:
		ret = tls13_recv_client_hello(conn);
		if (conn->early_data)
			next_state = TLS_state_early_data;
		else if (conn->hello_retry_request)
			next_state = TLS_state_hello_retry_request;
		else	next_state = TLS_state_server_hello;
		break;
]==]
[==[
	case TLS_state_client_hello:
		if (conn->ctx->min_protocol == TLS_protocol_tls12
			&& conn->ctx->max_protocol == TLS_protocol_tls13) {
			int selected_protocol = 0;
			ret = tls_server_client_hello_protocol(conn, &selected_protocol);
			if (ret != 1) return ret;
			if (selected_protocol == TLS_protocol_tls12) {
				conn->protocol = TLS_protocol_tls12;
				next_state = TLS_state_client_hello;
				break;
			}
			if (selected_protocol != TLS_protocol_tls13) {
				error_print();
				return -1;
			}
		}
		ret = tls13_recv_client_hello(conn);
		if (conn->early_data)
			next_state = TLS_state_early_data;
		else if (conn->hello_retry_request)
			next_state = TLS_state_hello_retry_request;
		else	next_state = TLS_state_server_hello;
		break;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	if (!(state == TLS_state_client_change_cipher_spec && ret == 0)) {
		tls_clean_record(conn);
	}
]==]
[==[
	if (!(state == TLS_state_client_change_cipher_spec && ret == 0)
		&& !(state == TLS_state_client_hello
			&& conn->protocol == TLS_protocol_tls12
			&& conn->ctx->min_protocol == TLS_protocol_tls12
			&& conn->ctx->max_protocol == TLS_protocol_tls13)) {
		tls_clean_record(conn);
	}
]==]
)

gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	while (conn->handshake_state != TLS_state_handshake_over) {

		ret = tls13_do_server_handshake(conn);
]==]
[==[
	while (conn->handshake_state != TLS_state_handshake_over) {

		if (conn->ctx->min_protocol == TLS_protocol_tls12
			&& conn->ctx->max_protocol == TLS_protocol_tls13
			&& conn->protocol == TLS_protocol_tls12) {
			return tls12_server_handshake(conn);
		}
		ret = tls13_do_server_handshake(conn);
]==]
)

# Peek the retained normal ServerHello and select TLS 1.3 from
# supported_versions, or TLS 1.2 from the legacy ServerHello version when the
# extension is absent.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
int tls13_do_client_handshake(TLS_CONNECT *conn)
]==]
[==[
static int tls_client_server_hello_protocol(TLS_CONNECT *conn, int *selected_protocol)
{
	int ret;
	int legacy_version;
	const uint8_t *random;
	const uint8_t *legacy_session_id_echo;
	size_t legacy_session_id_echo_len;
	int cipher_suite;
	const uint8_t *exts;
	size_t extslen;
	const uint8_t *supported_versions = NULL;
	size_t supported_versions_len = 0;

	if (!conn || !selected_protocol) {
		error_print();
		return -1;
	}
	if ((ret = tls_recv_record(conn)) != 1) {
		return ret;
	}
	if (tls_record_protocol(conn->record) != TLS_protocol_tls12
		|| tls_record_get_handshake_server_hello(conn->record,
			&legacy_version, &random,
			&legacy_session_id_echo, &legacy_session_id_echo_len,
			&cipher_suite, &exts, &extslen) != 1) {
		error_print();
		return -1;
	}
	while (extslen) {
		int ext_type;
		const uint8_t *ext_data;
		size_t ext_datalen;
		if (tls_ext_from_bytes(&ext_type, &ext_data, &ext_datalen, &exts, &extslen) != 1) {
			error_print();
			return -1;
		}
		if (ext_type == TLS_extension_supported_versions) {
			if (supported_versions || !ext_data) {
				error_print();
				return -1;
			}
			supported_versions = ext_data;
			supported_versions_len = ext_datalen;
		}
	}
	if (supported_versions) {
		if (tls13_server_supported_versions_from_bytes(
			selected_protocol, supported_versions, supported_versions_len) != 1) {
			error_print();
			return -1;
		}
	} else {
		*selected_protocol = legacy_version;
	}
	return 1;
}

int tls13_do_client_handshake(TLS_CONNECT *conn)
]==]
)

gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	case TLS_state_server_hello:
		ret = tls13_recv_server_hello(conn);
		if (tls13_ctx_accept_change_cipher_spec(conn->ctx))
			next_state = TLS_state_server_change_cipher_spec;
		else	next_state = TLS_state_encrypted_extensions;
		break;
]==]
[==[
	case TLS_state_server_hello:
		if (!conn->hello_retry_request
			&& conn->ctx->min_protocol == TLS_protocol_tls12
			&& conn->ctx->max_protocol == TLS_protocol_tls13) {
			int selected_protocol = 0;
			size_t i;
			ret = tls_client_server_hello_protocol(conn, &selected_protocol);
			if (ret != 1) return ret;
			if (selected_protocol == TLS_protocol_tls12) {
				conn->protocol = TLS_protocol_tls12;
				for (i = 0; i < conn->key_exchanges_cnt; i++) {
					x509_key_cleanup(&conn->key_exchanges[i]);
				}
				conn->key_exchanges_cnt = 0;
				conn->key_exchange_idx = 0;
				conn->key_share = 0;
				conn->key_exchange_modes = 0;
				ret = tls_recv_server_hello(conn);
				if (ret != 1) return ret;
				tls_clean_record(conn);
				conn->handshake_state = TLS_state_server_certificate;
				return TLS_ERROR_RECV_AGAIN;
			}
			if (selected_protocol != TLS_protocol_tls13) {
				error_print();
				return -1;
			}
		}
		ret = tls13_recv_server_hello(conn);
		if (tls13_ctx_accept_change_cipher_spec(conn->ctx))
			next_state = TLS_state_server_change_cipher_spec;
		else	next_state = TLS_state_encrypted_extensions;
		break;
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
unset(_gmssl_tls13_c)
