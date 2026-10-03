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
