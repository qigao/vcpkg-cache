# GmSSL port source transformations (phase 2/4): X.509 and RSA admission.
# Order-preserving consolidation: original source-bearing C/H inputs are now pinned in qigao/crypto.

# --- begin original x509-ca-eku.cmake (Git blob b043ed12790f97810bd8208e7ae8f94df004f6c5) ---
# RFC 5280 extended-key-usage constraints on certification authorities.

set(_gmssl_x509_ext_c "${SOURCE_PATH}/src/x509_ext.c")
set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_cer.c")

# x509_exts_check() validates a certificate's structural role. An EKU on a CA
# constrains paths issued by that CA; it is not itself a leaf-certificate use.
# Parse the extension here and defer the requested-purpose check to chain
# validation, which knows whether the path is for server or client auth.
gmssl_replace_once(
    "${_gmssl_x509_ext_c}"
[==[
		case OID_ce_ext_key_usage:
			if (x509_ext_key_usage_from_der(ext_key_usages, &ext_key_usages_cnt,
					sizeof(ext_key_usages)/sizeof(ext_key_usages[0]), &val, &vlen) != 1
				|| x509_ext_key_usage_check(ext_key_usages, ext_key_usages_cnt, cert_type) != 1) {
				error_print();
				return -1;
			}
			break;
]==]
[==[
		case OID_ce_ext_key_usage:
			if (x509_ext_key_usage_from_der(ext_key_usages, &ext_key_usages_cnt,
					sizeof(ext_key_usages)/sizeof(ext_key_usages[0]), &val, &vlen) != 1) {
				error_print();
				return -1;
			}
			if (!is_ca
				&& x509_ext_key_usage_check(ext_key_usages, ext_key_usages_cnt, cert_type) != 1) {
				error_print();
				return -1;
			}
			break;
]==]
)

# Validate an intermediate/root CA's EKU against the purpose of the path. A CA
# without EKU is unrestricted; anyExtendedKeyUsage or the requested purpose is
# accepted. A serverAuth-only CA therefore cannot validate a client-auth path.
gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
static void x509_verify_set_result(int *verify_result, int result)
{
	if (verify_result) {
		*verify_result = result;
	}
}
]==]
[==[
static void x509_verify_set_result(int *verify_result, int result)
{
	if (verify_result) {
		*verify_result = result;
	}
}

static int x509_cert_check_ca_key_purpose(const uint8_t *cert, size_t certlen,
	int entity_cert_type)
{
	const uint8_t *exts;
	size_t extslen;
	const uint8_t *val;
	size_t vlen;
	int critical;
	int key_purposes[X509_MAX_KEY_PURPOSES];
	size_t key_purposes_cnt;
	size_t i;
	int ret;

	if (x509_cert_get_exts(cert, certlen, &exts, &extslen) != 1) {
		error_print();
		return -1;
	}
	ret = x509_exts_get_ext_by_oid(exts, extslen, OID_ce_ext_key_usage,
		&critical, &val, &vlen);
	if (ret < 0) {
		error_print();
		return -1;
	}
	if (ret == 0) {
		return 1;
	}
	if (x509_ext_key_usage_from_der(key_purposes, &key_purposes_cnt,
			sizeof(key_purposes)/sizeof(key_purposes[0]), &val, &vlen) != 1
		|| vlen != 0) {
		error_print();
		return -1;
	}
	for (i = 0; i < key_purposes_cnt; i++) {
		if (key_purposes[i] == OID_any_extended_key_usage) {
			return 1;
		}
	}
	return x509_ext_key_usage_check(
		key_purposes, key_purposes_cnt, entity_cert_type) == 1 ? 1 : 0;
}

static int x509_cert_check_ca_for_purpose(const uint8_t *cert, size_t certlen,
	int entity_cert_type)
{
	if (x509_cert_check(cert, certlen, X509_cert_ca) != 1
		|| x509_cert_check_ca_key_purpose(cert, certlen, entity_cert_type) != 1) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
)

# Standard TLS chain: enforce the entity purpose for every CA and trust anchor.
foreach(_gmssl_x509_standard_ca_check RANGE 1 2)
    gmssl_replace_once(
        "${_gmssl_x509_c}"
        "x509_cert_check(cacert, cacertlen, X509_cert_ca)"
        "x509_cert_check_ca_for_purpose(cacert, cacertlen, entity_cert_type)"
    )
endforeach()

# TLCP chain: the signing certificate determines the authentication purpose.
foreach(_gmssl_x509_tlcp_ca_check RANGE 1 2)
    gmssl_replace_once(
        "${_gmssl_x509_c}"
        "x509_cert_check(cacert, cacertlen, X509_cert_ca)"
        "x509_cert_check_ca_for_purpose(cacert, cacertlen, sign_cert_type)"
    )
endforeach()

file(READ "${_gmssl_x509_ext_c}" _gmssl_x509_ca_eku_ext_after)
file(READ "${_gmssl_x509_c}" _gmssl_x509_ca_eku_cer_after)
foreach(_needle
    "if (!is_ca"
    "static int x509_cert_check_ca_key_purpose"
    "x509_cert_check_ca_for_purpose(cacert, cacertlen, entity_cert_type)"
    "x509_cert_check_ca_for_purpose(cacert, cacertlen, sign_cert_type)")
    string(FIND "${_gmssl_x509_ca_eku_ext_after}${_gmssl_x509_ca_eku_cer_after}"
        "${_needle}" _offset)
    if(_offset EQUAL -1)
        message(FATAL_ERROR "GmSSL CA EKU path constraint missing: ${_needle}")
    endif()
endforeach()

unset(_offset)
unset(_needle)
unset(_gmssl_x509_ca_eku_cer_after)
unset(_gmssl_x509_ca_eku_ext_after)
unset(_gmssl_x509_tlcp_ca_check)
unset(_gmssl_x509_standard_ca_check)
unset(_gmssl_x509_c)
unset(_gmssl_x509_ext_c)
# --- end original x509-ca-eku.cmake ---

# --- begin original certificate-chain-capacity.cmake (Git blob 67e66e219584ab5ea8b8d26d3661b54597e5a705) ---
# TLS Certificate messages commonly exceed 4 KiB with modern public-PKI chains.
# Match TLS_CTX's existing 8 KiB certificate-chain storage while keeping
# TLS_CONNECT bounded.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")

gmssl_replace_once(
    "${_gmssl_tls_h}"
    "#define TLS_MAX_CERTIFICATES_SIZE\t4096"
    "#define TLS_MAX_CERTIFICATES_SIZE\t8192"
)

file(READ "${_gmssl_tls_h}" _gmssl_certificate_capacity_after)
string(FIND "${_gmssl_certificate_capacity_after}"
    "#define TLS_MAX_CERTIFICATES_SIZE\t8192"
    _gmssl_certificate_capacity_offset)
if(_gmssl_certificate_capacity_offset EQUAL -1)
    message(FATAL_ERROR "GmSSL TLS certificate-chain capacity adaptation missing")
endif()

unset(_gmssl_certificate_capacity_offset)
unset(_gmssl_certificate_capacity_after)
unset(_gmssl_tls_h)
# --- end original certificate-chain-capacity.cmake ---

# --- begin original inspection.cmake (Git blob de41019213ffa208cc0faeafdd1ff075b512b6a2) ---
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
# --- end original inspection.cmake ---

# --- begin original exporter.cmake (Git blob c83cdb425c474b30e0b7147b24b3821940e8c5af) ---
# RFC 5705 / RFC 8446 exporter keying material for the GmSSL overlay.
# Required by Salts/CNet's 32-byte EXPORTER-Channel-Binding contract.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")
set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
	uint8_t master_secret[48];
	uint8_t resumption_master_secret[48];
]==]
[==[
	uint8_t master_secret[48];
	uint8_t exporter_master_secret[32];
	uint8_t resumption_master_secret[48];
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_shutdown(TLS_CONNECT *conn);
void tls_cleanup(TLS_CONNECT *conn);
]==]
[==[
#define TLS_EXPORTER_CONTEXT_MAX_SIZE 1024

int tls_shutdown(TLS_CONNECT *conn);
int tls_export_keying_material(TLS_CONNECT *conn, uint8_t *out, size_t outlen,
	const char *label, const uint8_t *context, size_t contextlen, int use_context);
void tls_cleanup(TLS_CONNECT *conn);
]==]
)

# RFC 8446 section 7.1: exporter_master_secret is derived from the master
# secret with the transcript through server Finished, exactly alongside the
# application traffic secrets.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	if (tls13_derive_secret(conn->master_secret, "c ap traffic", &conn->dgst_ctx, conn->client_application_traffic_secret) != 1
		|| tls13_derive_secret(conn->master_secret, "s ap traffic", &conn->dgst_ctx, conn->server_application_traffic_secret) != 1) {
]==]
[==[
	if (tls13_derive_secret(conn->master_secret, "c ap traffic", &conn->dgst_ctx, conn->client_application_traffic_secret) != 1
		|| tls13_derive_secret(conn->master_secret, "s ap traffic", &conn->dgst_ctx, conn->server_application_traffic_secret) != 1
		|| tls13_derive_secret(conn->master_secret, "exp master", &conn->dgst_ctx, conn->exporter_master_secret) != 1) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_shutdown(TLS_CONNECT *conn)
{
]==]
[==[
int tls_export_keying_material(TLS_CONNECT *conn, uint8_t *out, size_t outlen,
	const char *label, const uint8_t *context, size_t contextlen, int use_context)
{
	if (!conn || !out || !outlen || !label || !label[0]
		|| (contextlen && !context)
		|| conn->handshake_state != TLS_state_handshake_over
		|| !conn->digest) {
		error_print();
		return -1;
	}

	if (conn->protocol == TLS_protocol_tls12) {
		if (use_context) {
			uint8_t more[32 + 2 + TLS_EXPORTER_CONTEXT_MAX_SIZE];
			size_t morelen;

			if (contextlen > TLS_EXPORTER_CONTEXT_MAX_SIZE || contextlen > 0xffff) {
				error_print();
				return -1;
			}
			memcpy(more, conn->server_random, 32);
			more[32] = (uint8_t)(contextlen >> 8);
			more[33] = (uint8_t)contextlen;
			if (contextlen) {
				memcpy(more + 34, context, contextlen);
			}
			morelen = 34 + contextlen;
			if (tls_prf(conn->digest, conn->master_secret, sizeof(conn->master_secret),
				label, conn->client_random, sizeof(conn->client_random),
				more, morelen, outlen, out) != 1) {
				gmssl_secure_clear(more, sizeof(more));
				error_print();
				return -1;
			}
			gmssl_secure_clear(more, sizeof(more));
			return 1;
		}
		return tls_prf(conn->digest, conn->master_secret, sizeof(conn->master_secret),
			label, conn->client_random, sizeof(conn->client_random),
			conn->server_random, sizeof(conn->server_random), outlen, out);
	}

	if (conn->protocol == TLS_protocol_tls13) {
		DIGEST_CTX empty_ctx;
		uint8_t derived_secret[DIGEST_MAX_SIZE];
		uint8_t context_hash[DIGEST_MAX_SIZE];
		size_t context_hash_len = 0;
		int ret = -1;

		if (conn->digest->digest_size > sizeof(derived_secret)
			|| digest_init(&empty_ctx, conn->digest) != 1
			|| tls13_derive_secret(conn->exporter_master_secret, label,
				&empty_ctx, derived_secret) != 1
			|| digest(conn->digest,
				use_context ? context : NULL,
				use_context ? contextlen : 0,
				context_hash, &context_hash_len) != 1
			|| context_hash_len != conn->digest->digest_size
			|| tls13_hkdf_expand_label(conn->digest, derived_secret, "exporter",
				context_hash, context_hash_len, outlen, out) != 1) {
			error_print();
			goto end;
		}
		ret = 1;
end:
		gmssl_secure_clear(&empty_ctx, sizeof(empty_ctx));
		gmssl_secure_clear(derived_secret, sizeof(derived_secret));
		gmssl_secure_clear(context_hash, sizeof(context_hash));
		return ret;
	}

	error_print();
	return -1;
}

int tls_shutdown(TLS_CONNECT *conn)
{
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
unset(_gmssl_tls13_c)
# --- end original exporter.cmake ---

# --- begin original version-range.cmake (Git blob c3b631a18af286b25df3b301b26329cade4eb766) ---
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
# --- end original version-range.cmake ---

# --- begin original strict-versions.cmake (Git blob 09550cf03b0aea51c2ea682147802882c93ddca0) ---
# #192: CNet RFC 8998/TLCP exact-version admission over pinned GmSSL.
# Exported only by the private provider; never by Salts::Core/CNet.
# GmSSL upstream implements tls_ctx_set_supported_versions without declaring
# it in the installed public header. Restrict to one validated exact version.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_set_protocol_range(TLS_CTX *ctx, int min_protocol, int max_protocol);
int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt);
]==]
[==[
int tls_ctx_set_protocol_range(TLS_CTX *ctx, int min_protocol, int max_protocol);
/* Exact-version pre-configuration policy for TLS 1.2/1.3 or TLCP.
 * Valid only directly after tls_ctx_init and before other policy/keys.
 * On failure the provider context is not modified.
 */
int tls_ctx_set_strict_protocol(TLS_CTX *ctx, int protocol);
int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt);
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt)
]==]
[==[
int tls_ctx_set_strict_protocol(TLS_CTX *ctx, int protocol)
{
    if (!ctx
        || (protocol != TLS_protocol_tls13
            && protocol != TLS_protocol_tls12
            && protocol != TLS_protocol_tlcp)
        || ctx->protocol != protocol
        || ctx->min_protocol != protocol
        || ctx->max_protocol != protocol
        || ctx->cipher_suites_cnt != 0
        || ctx->supported_groups_cnt != 0
        || ctx->signature_algorithms_cnt != 0
        || ctx->x509_keys_cnt != 0) {
        error_print();
        return -1;
    }
    /* The internal GmSSL setter validates the sole element before
     * assignment; no mixed version list or partial mutation is admitted. */
    return tls_ctx_set_supported_versions(ctx, &protocol, 1);
}

int tls_ctx_set_cipher_suites(TLS_CTX *ctx, const int *cipher_suites, size_t cipher_suites_cnt)
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
# --- end original strict-versions.cmake ---

# --- begin original signature-capacity.cmake (Git blob 9383f701caf2737c55f59be4ee8ead3c10e1b3b4) ---
# Standard TLS signature-algorithm capacity/range contract.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
	int signature_algorithms[2];
	size_t signature_algorithms_cnt;
]==]
[==[
	int signature_algorithms[8];
	size_t signature_algorithms_cnt;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	if (sig_algs_cnt > sizeof(ctx->signature_algorithms)/sizeof(ctx->signature_algorithms[0])) {
		error_print();
		return -1;
	}

	switch (ctx->protocol) {
]==]
[==[
	if (sig_algs_cnt > sizeof(ctx->signature_algorithms)/sizeof(ctx->signature_algorithms[0])) {
		error_print();
		return -1;
	}
	if (ctx->min_protocol == TLS_protocol_tls12
		&& ctx->max_protocol == TLS_protocol_tls13) {
		for (i = 0; i < sig_algs_cnt; i++) {
			if (!tls_type_is_in_list(sig_algs[i],
					tls13_signature_algorithms, tls13_signature_algorithms_cnt)
				&& !tls_type_is_in_list(sig_algs[i],
					tls12_signature_algorithms, tls12_signature_algorithms_cnt)) {
				error_print();
				return -1;
			}
		}
		memcpy(ctx->signature_algorithms, sig_algs,
			sig_algs_cnt * sizeof(sig_algs[0]));
		ctx->signature_algorithms_cnt = sig_algs_cnt;
		return 1;
	}

	switch (ctx->protocol) {
]==]
)

# tls_ctx_check() must validate the same TLS 1.2/1.3 union accepted by
# tls_ctx_set_signature_algorithms() for a standard version-range context.
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	for (i = 0; i < ctx->signature_algorithms_cnt; i++) {
		if (!tls_type_is_in_list(ctx->signature_algorithms[i],
			supported_sig_algs, supported_sig_algs_cnt)) {
			error_print();
			return -1;
		}
	}
]==]
[==[
	for (i = 0; i < ctx->signature_algorithms_cnt; i++) {
		if (standard_tls_range) {
			if (!tls_type_is_in_list(ctx->signature_algorithms[i],
					tls13_signature_algorithms, tls13_signature_algorithms_cnt)
				&& !tls_type_is_in_list(ctx->signature_algorithms[i],
					tls12_signature_algorithms, tls12_signature_algorithms_cnt)) {
				error_print();
				return -1;
			}
		} else if (!tls_type_is_in_list(ctx->signature_algorithms[i],
				supported_sig_algs, supported_sig_algs_cnt)) {
			error_print();
			return -1;
		}
	}
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
# --- end original signature-capacity.cmake ---

# --- begin original ec-plain-pkcs8.cmake (Git blob 2ce37b8b7890b0ac057d8a3c0df942e384394a17) ---
# Unencrypted EC PKCS#8 PrivateKeyInfo loading required by Salts identities.
# Keep the existing password-bearing encrypted EC/SM2 path unchanged.

set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
]==]
[==[
static int x509_plain_ec_private_key_info_from_pem(X509_KEY *key, FILE *fp)
{
	enum { X509_PLAIN_EC_PKCS8_MAX_DER_SIZE = 4096 };
	uint8_t buf[X509_PLAIN_EC_PKCS8_MAX_DER_SIZE];
	const uint8_t *p = buf;
	size_t len = 0;
	const uint8_t *attrs = NULL;
	size_t attrslen = 0;
	int ret = -1;

	memset(buf, 0, sizeof(buf));
	if (!key || !fp) {
		error_print();
		return -1;
	}
	if (pem_read(fp, "PRIVATE KEY", buf, &len, sizeof(buf)) != 1
		|| x509_private_key_info_from_der(key, &attrs, &attrslen, &p, &len) != 1
		|| asn1_length_is_zero(len) != 1
		|| attrslen != 0
		|| key->algor != OID_ec_public_key
		|| key->algor_param != OID_secp256r1) {
		error_print();
		goto end;
	}
	ret = 1;

end:
	gmssl_secure_clear(buf, sizeof(buf));
	if (ret != 1) {
		x509_key_cleanup(key);
	}
	return ret;
}

int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (algor == OID_ec_public_key) {
		int ret;
		const uint8_t *attrs;
		size_t attrslen;
		if (!pass) {
			error_print();
			return -1;
		}
		if ((ret = x509_private_key_info_decrypt_from_pem(key, &attrs, &attrslen, pass, fp)) < 0) {
			error_print();
			return -1;
		} else if (ret == 0) {
			return 0; // TODO: support return 0 for other algors
		}
	}
]==]
[==[
	if (algor == OID_ec_public_key) {
		int ret;
		const uint8_t *attrs;
		size_t attrslen;
		if (pass && pass[0]) {
			if ((ret = x509_private_key_info_decrypt_from_pem(
					key, &attrs, &attrslen, pass, fp)) < 0) {
				error_print();
				return -1;
			} else if (ret == 0) {
				return 0;
			}
		} else {
			if (x509_plain_ec_private_key_info_from_pem(key, fp) != 1) {
				error_print();
				return -1;
			}
		}
	}
]==]
)

unset(_gmssl_x509_c)
# --- end original ec-plain-pkcs8.cmake ---

# --- begin original rsa-verify.cmake (Git blob 8d232c0327c2d57267a53e65d978fcf31d5de348) ---
# Bounded RSA public-key ABI and import for standard TLS authentication.
# Public/private arithmetic is shared in rsa_private_op.c.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

vcpkg_replace_string(
    "${_gmssl_rsa_h}"
    "int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);"
    "#define RSA_MIN_MODULUS_SIZE 256\n#define RSA_MAX_MODULUS_SIZE 512\n#define RSA_MAX_MODULUS_WORDS (RSA_MAX_MODULUS_SIZE / 4)\n\ntypedef struct {\n\tsize_t modulus_size;\n\tuint8_t modulus[RSA_MAX_MODULUS_SIZE];\n\tuint32_t public_exponent;\n} RSA_PUBLIC_KEY;\n\nint rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);\nint rsa_public_key_operation(const RSA_PUBLIC_KEY *key,\n\tconst uint8_t *in, size_t inlen,\n\tuint8_t *out, size_t outmax, size_t *outlen);\nint rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "#include <gmssl/rsa.h>\n#include <gmssl/asn1.h>"
    "#include <gmssl/rsa.h>\n#include <gmssl/bn.h>\n#include <gmssl/mem.h>\n#include <gmssl/asn1.h>"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)\n{"
    [==[
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen)
{
	const uint8_t *d;
	size_t dlen;
	const uint8_t *modulus;
	size_t modulus_len;
	int exponent;

	if (!key || !in || !inlen) {
		error_print();
		return -1;
	}
	memset(key, 0, sizeof(*key));
	if (asn1_sequence_from_der(&d, &dlen, in, inlen) != 1
		|| asn1_integer_from_der(&modulus, &modulus_len, &d, &dlen) != 1
		|| asn1_int_from_der(&exponent, &d, &dlen) != 1
		|| asn1_length_is_zero(dlen) != 1) {
		error_print();
		return -1;
	}
	/* DER INTEGER may carry one sign-padding zero for a positive modulus. */
	if (modulus_len > 1 && modulus[0] == 0) {
		modulus++;
		modulus_len--;
	}
	if (modulus_len < RSA_MIN_MODULUS_SIZE
		|| modulus_len > RSA_MAX_MODULUS_SIZE
		|| (modulus_len & 3u) != 0
		|| modulus[0] == 0
		|| (modulus[modulus_len - 1] & 1u) == 0
		|| exponent < 3
		|| (exponent & 1) == 0) {
		error_print();
		return -1;
	}
	key->modulus_size = modulus_len;
	memcpy(key->modulus, modulus, modulus_len);
	key->public_exponent = (uint32_t)exponent;
	return 1;
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
# --- end original rsa-verify.cmake ---

# --- begin original rsa-signatures.cmake (Git blob ee4c92c0c4a3d361c3f647fd92ac45b49138519b) ---
# RSA signature encoding verification built on the bounded raw public operation.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

vcpkg_replace_string(
    "${_gmssl_rsa_h}"
    "int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);"
    "int rsa_verify_pkcs1_v15_sha256(const RSA_PUBLIC_KEY *key,\n\tconst uint8_t dgst[32], const uint8_t *sig, size_t siglen);\nint rsa_verify_pss_sha256(const RSA_PUBLIC_KEY *key,\n\tconst uint8_t dgst[32], const uint8_t *sig, size_t siglen);\nint rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "#include <gmssl/mem.h>\n#include <gmssl/asn1.h>"
    "#include <gmssl/mem.h>\n#include <gmssl/sha2.h>\n#include <gmssl/asn1.h>"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)\n{"
    [==[
static int rsa_mgf1_sha256(const uint8_t *seed, size_t seedlen, uint8_t *out, size_t outlen)
{
	uint32_t counter = 0;

	if ((!seed && seedlen) || (!out && outlen)) {
		error_print();
		return -1;
	}
	while (outlen) {
		SHA256_CTX ctx;
		uint8_t block[SHA256_DIGEST_SIZE];
		uint8_t count[4];
		size_t n = outlen < sizeof(block) ? outlen : sizeof(block);

		count[0] = (uint8_t)(counter >> 24);
		count[1] = (uint8_t)(counter >> 16);
		count[2] = (uint8_t)(counter >> 8);
		count[3] = (uint8_t)counter;
		sha256_init(&ctx);
		sha256_update(&ctx, seed, seedlen);
		sha256_update(&ctx, count, sizeof(count));
		sha256_finish(&ctx, block);
		memcpy(out, block, n);
		out += n;
		outlen -= n;
		counter++;
		gmssl_secure_clear(&ctx, sizeof(ctx));
		gmssl_secure_clear(block, sizeof(block));
	}
	return 1;
}

static size_t rsa_modulus_bits(const RSA_PUBLIC_KEY *key)
{
	uint8_t b;
	size_t bits;

	if (!key || !key->modulus_size || key->modulus[0] == 0) return 0;
	b = key->modulus[0];
	bits = (key->modulus_size - 1) * 8;
	while (b) {
		bits++;
		b >>= 1;
	}
	return bits;
}

int rsa_verify_pkcs1_v15_sha256(const RSA_PUBLIC_KEY *key,
	const uint8_t dgst[32], const uint8_t *sig, size_t siglen)
{
	static const uint8_t digest_info_prefix[] = {
		0x30,0x31,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,0x01,
		0x65,0x03,0x04,0x02,0x01,0x05,0x00,0x04,0x20
	};
	uint8_t em[RSA_MAX_MODULUS_SIZE];
	size_t emlen = 0;
	size_t i;
	int ret = 0;

	if (!key || !dgst || !sig || siglen != key->modulus_size) {
		error_print();
		return -1;
	}
	if (rsa_public_key_operation(key, sig, siglen, em, sizeof(em), &emlen) != 1) {
		return 0;
	}
	if (emlen < 3 + 8 + sizeof(digest_info_prefix) + SHA256_DIGEST_SIZE
		|| em[0] != 0x00 || em[1] != 0x01) {
		goto end;
	}
	i = 2;
	while (i < emlen && em[i] == 0xff) i++;
	if (i < 10 || i >= emlen || em[i] != 0x00) goto end;
	i++;
	if (emlen - i != sizeof(digest_info_prefix) + SHA256_DIGEST_SIZE) goto end;
	if (gmssl_secure_memcmp(em + i, digest_info_prefix, sizeof(digest_info_prefix)) != 0) goto end;
	i += sizeof(digest_info_prefix);
	if (gmssl_secure_memcmp(em + i, dgst, SHA256_DIGEST_SIZE) != 0) goto end;
	ret = 1;

end:
	gmssl_secure_clear(em, sizeof(em));
	return ret;
}

int rsa_verify_pss_sha256(const RSA_PUBLIC_KEY *key,
	const uint8_t dgst[32], const uint8_t *sig, size_t siglen)
{
	enum { SALT_LEN = SHA256_DIGEST_SIZE };
	uint8_t recovered[RSA_MAX_MODULUS_SIZE];
	uint8_t db[RSA_MAX_MODULUS_SIZE];
	uint8_t mask[RSA_MAX_MODULUS_SIZE];
	uint8_t expected_h[SHA256_DIGEST_SIZE];
	uint8_t prefix[8] = {0};
	SHA256_CTX hash_ctx;
	size_t recovered_len = 0;
	size_t mod_bits;
	size_t em_bits;
	size_t em_len;
	size_t offset;
	size_t db_len;
	size_t ps_len;
	size_t unused_bits;
	const uint8_t *em;
	const uint8_t *h;
	const uint8_t *salt;
	size_t i;
	int ret = 0;

	if (!key || !dgst || !sig || siglen != key->modulus_size) {
		error_print();
		return -1;
	}
	mod_bits = rsa_modulus_bits(key);
	if (mod_bits < 2) return -1;
	em_bits = mod_bits - 1;
	em_len = (em_bits + 7) / 8;
	if (em_len < SHA256_DIGEST_SIZE + SALT_LEN + 2
		|| key->modulus_size < em_len
		|| key->modulus_size - em_len > 1) {
		error_print();
		return -1;
	}
	if (rsa_public_key_operation(key, sig, siglen,
			recovered, sizeof(recovered), &recovered_len) != 1) {
		return 0;
	}
	if (recovered_len != key->modulus_size) goto end;
	offset = recovered_len - em_len;
	for (i = 0; i < offset; i++) {
		if (recovered[i] != 0) goto end;
	}
	em = recovered + offset;
	if (em[em_len - 1] != 0xbc) goto end;

	db_len = em_len - SHA256_DIGEST_SIZE - 1;
	h = em + db_len;
	unused_bits = 8 * em_len - em_bits;
	if (unused_bits > 7) goto end;
	if (unused_bits && (em[0] & (uint8_t)(0xffu << (8 - unused_bits))) != 0) goto end;

	if (rsa_mgf1_sha256(h, SHA256_DIGEST_SIZE, mask, db_len) != 1) goto end;
	for (i = 0; i < db_len; i++) db[i] = em[i] ^ mask[i];
	if (unused_bits) db[0] &= (uint8_t)(0xffu >> unused_bits);

	ps_len = em_len - SHA256_DIGEST_SIZE - SALT_LEN - 2;
	for (i = 0; i < ps_len; i++) {
		if (db[i] != 0) goto end;
	}
	if (db[ps_len] != 0x01) goto end;
	salt = db + ps_len + 1;

	sha256_init(&hash_ctx);
	sha256_update(&hash_ctx, prefix, sizeof(prefix));
	sha256_update(&hash_ctx, dgst, SHA256_DIGEST_SIZE);
	sha256_update(&hash_ctx, salt, SALT_LEN);
	sha256_finish(&hash_ctx, expected_h);
	if (gmssl_secure_memcmp(h, expected_h, SHA256_DIGEST_SIZE) != 0) goto end;
	ret = 1;

end:
	gmssl_secure_clear(recovered, sizeof(recovered));
	gmssl_secure_clear(db, sizeof(db));
	gmssl_secure_clear(mask, sizeof(mask));
	gmssl_secure_clear(expected_h, sizeof(expected_h));
	gmssl_secure_clear(&hash_ctx, sizeof(hash_ctx));
	return ret;
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
# --- end original rsa-signatures.cmake ---

# --- begin original rsa-private.cmake (Git blob 51e38d78471585385384f685b1c6a96182b2b10c) ---
# Bounded RSA private-key representation and strict PKCS#1 parser.
# This slice intentionally stops before private modular exponentiation/signing.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
typedef struct {
	size_t modulus_size;
	uint8_t modulus[RSA_MAX_MODULUS_SIZE];
	uint32_t public_exponent;
} RSA_PUBLIC_KEY;
]==]
[==[
typedef struct {
	size_t modulus_size;
	uint8_t modulus[RSA_MAX_MODULUS_SIZE];
	uint32_t public_exponent;
} RSA_PUBLIC_KEY;

#define RSA_MAX_PRIME_SIZE (RSA_MAX_MODULUS_SIZE / 2)

typedef struct {
	RSA_PUBLIC_KEY public_key;
	size_t prime_size;
	uint8_t prime1[RSA_MAX_PRIME_SIZE];
	uint8_t prime2[RSA_MAX_PRIME_SIZE];
	uint8_t exponent1[RSA_MAX_PRIME_SIZE];
	uint8_t exponent2[RSA_MAX_PRIME_SIZE];
	uint8_t coefficient[RSA_MAX_PRIME_SIZE];
} RSA_PRIVATE_KEY;
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);
]==]
[==[
int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
[==[
static int rsa_private_component_copy(uint8_t *out, size_t outlen,
	const uint8_t *in, size_t inlen)
{
	if (!out || !outlen || !in || !inlen) {
		error_print();
		return -1;
	}
	if (inlen > 1 && in[0] == 0) {
		in++;
		inlen--;
	}
	if (!inlen || inlen > outlen) {
		error_print();
		return -1;
	}
	memset(out, 0, outlen);
	memcpy(out + outlen - inlen, in, inlen);
	return 1;
}

int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen)
{
	const uint8_t *d;
	size_t dlen;
	int version;
	const uint8_t *n;
	size_t nlen;
	int e;
	const uint8_t *private_exponent;
	size_t private_exponent_len;
	const uint8_t *p;
	size_t plen;
	const uint8_t *q;
	size_t qlen;
	const uint8_t *dP;
	size_t dPlen;
	const uint8_t *dQ;
	size_t dQlen;
	const uint8_t *qInv;
	size_t qInvlen;
	uint32_t p_bn[RSA_MAX_PRIME_SIZE / 4];
	uint32_t q_bn[RSA_MAX_PRIME_SIZE / 4];
	uint32_t product[RSA_MAX_MODULUS_WORDS];
	uint32_t exponent1_bn[RSA_MAX_PRIME_SIZE / 4];
	uint32_t exponent2_bn[RSA_MAX_PRIME_SIZE / 4];
	uint32_t coefficient_bn[RSA_MAX_PRIME_SIZE / 4];
	uint8_t product_bytes[RSA_MAX_MODULUS_SIZE];
	size_t k;
	int ret = -1;

	if (!key || !in || !*in || !inlen) {
		error_print();
		return -1;
	}
	memset(key, 0, sizeof(*key));
	memset(p_bn, 0, sizeof(p_bn));
	memset(q_bn, 0, sizeof(q_bn));
	memset(product, 0, sizeof(product));
	memset(exponent1_bn, 0, sizeof(exponent1_bn));
	memset(exponent2_bn, 0, sizeof(exponent2_bn));
	memset(coefficient_bn, 0, sizeof(coefficient_bn));
	memset(product_bytes, 0, sizeof(product_bytes));

	if (asn1_sequence_from_der(&d, &dlen, in, inlen) != 1
		|| asn1_int_from_der(&version, &d, &dlen) != 1
		|| asn1_integer_from_der(&n, &nlen, &d, &dlen) != 1
		|| asn1_int_from_der(&e, &d, &dlen) != 1
		|| asn1_integer_from_der(&private_exponent, &private_exponent_len, &d, &dlen) != 1
		|| asn1_integer_from_der(&p, &plen, &d, &dlen) != 1
		|| asn1_integer_from_der(&q, &qlen, &d, &dlen) != 1
		|| asn1_integer_from_der(&dP, &dPlen, &d, &dlen) != 1
		|| asn1_integer_from_der(&dQ, &dQlen, &d, &dlen) != 1
		|| asn1_integer_from_der(&qInv, &qInvlen, &d, &dlen) != 1
		|| asn1_length_is_zero(dlen) != 1) {
		error_print();
		goto end;
	}
	if (version != 0) {
		error_print();
		goto end;
	}
	if (nlen > 1 && n[0] == 0) {
		n++;
		nlen--;
	}
	if (nlen < RSA_MIN_MODULUS_SIZE
		|| nlen > RSA_MAX_MODULUS_SIZE
		|| (nlen & 7u) != 0
		|| n[0] == 0
		|| (n[nlen - 1] & 1u) == 0
		|| e < 3 || (e & 1) == 0
		|| private_exponent_len == 0 || private_exponent_len > nlen + 1) {
		error_print();
		goto end;
	}

	key->public_key.modulus_size = nlen;
	memcpy(key->public_key.modulus, n, nlen);
	key->public_key.public_exponent = (uint32_t)e;
	key->prime_size = nlen / 2;

	if (rsa_private_component_copy(key->prime1, key->prime_size, p, plen) != 1
		|| rsa_private_component_copy(key->prime2, key->prime_size, q, qlen) != 1
		|| rsa_private_component_copy(key->exponent1, key->prime_size, dP, dPlen) != 1
		|| rsa_private_component_copy(key->exponent2, key->prime_size, dQ, dQlen) != 1
		|| rsa_private_component_copy(key->coefficient, key->prime_size, qInv, qInvlen) != 1) {
		error_print();
		goto end;
	}
	if ((key->prime1[key->prime_size - 1] & 1u) == 0
		|| (key->prime2[key->prime_size - 1] & 1u) == 0
		|| key->prime1[0] == 0 || key->prime2[0] == 0) {
		error_print();
		goto end;
	}

	k = key->prime_size / 4;
	bn_from_bytes(p_bn, k, key->prime1);
	bn_from_bytes(q_bn, k, key->prime2);
	bn_from_bytes(exponent1_bn, k, key->exponent1);
	bn_from_bytes(exponent2_bn, k, key->exponent2);
	bn_from_bytes(coefficient_bn, k, key->coefficient);
	if (bn_cmp(p_bn, q_bn, k) == 0
		|| bn_is_zero(exponent1_bn, k)
		|| bn_cmp(exponent1_bn, p_bn, k) >= 0
		|| bn_is_zero(exponent2_bn, k)
		|| bn_cmp(exponent2_bn, q_bn, k) >= 0
		|| bn_is_zero(coefficient_bn, k)
		|| bn_cmp(coefficient_bn, p_bn, k) >= 0) {
		error_print();
		goto end;
	}
	bn_mul(product, p_bn, q_bn, k);
	bn_to_bytes(product, k * 2, product_bytes);
	if (gmssl_secure_memcmp(product_bytes,
		key->public_key.modulus, key->public_key.modulus_size) != 0) {
		error_print();
		goto end;
	}

	ret = 1;

end:
	if (ret != 1) {
		gmssl_secure_clear(key, sizeof(*key));
	}
	gmssl_secure_clear(p_bn, sizeof(p_bn));
	gmssl_secure_clear(q_bn, sizeof(q_bn));
	gmssl_secure_clear(product, sizeof(product));
	gmssl_secure_clear(exponent1_bn, sizeof(exponent1_bn));
	gmssl_secure_clear(exponent2_bn, sizeof(exponent2_bn));
	gmssl_secure_clear(coefficient_bn, sizeof(coefficient_bn));
	gmssl_secure_clear(product_bytes, sizeof(product_bytes));
	return ret;
}

void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key)
{
	if (key) {
		gmssl_secure_clear(key, sizeof(*key));
	}
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
# --- end original rsa-private.cmake ---

# --- begin original rsa-private-op.cmake (Git blob 4b1ff1fd588b2827669039c750d2aee78767e305) ---
# Bounded RSA private CRT with fixed-width arithmetic, random blinding and
# result verification. Keep the existing public ABI; own the implementation in
# a normal provider source file rather than embedding it in a CMake string.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
[==[
int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen);
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
)

file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/src/rsa_private_op.c"
     DESTINATION "${SOURCE_PATH}/src")
file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/include/gmssl/rsa_components.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c" "src/debug.c\nsrc/rsa_private_op.c")
unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
# --- end original rsa-private-op.cmake ---

