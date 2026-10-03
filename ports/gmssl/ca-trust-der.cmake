# Owned in-memory CA trust injection for platform/default trust discovery.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_cert_c "${SOURCE_PATH}/src/tls_cert.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
]==]
[==[
int tls_ctx_set_ca_certificates_der(TLS_CTX *ctx,
	const uint8_t *certs, size_t certslen, int depth);
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth)
{
]==]
[==[
int tls_ctx_set_ca_certificates_der(TLS_CTX *ctx,
	const uint8_t *certs, size_t certslen, int depth)
{
	const uint8_t *p = certs;
	size_t len = certslen;
	const uint8_t *cert;
	size_t certlen;
	const uint8_t *subject;
	size_t subject_len;
	uint8_t *owned = NULL;
	size_t count = 0;

	if (!ctx || !certs || !certslen) {
		error_print();
		return -1;
	}
	if (depth < 0 || depth > TLS_MAX_VERIFY_DEPTH) {
		error_print();
		return -1;
	}
	if (!tls_protocol_name(ctx->protocol) || ctx->cacerts) {
		error_print();
		return -1;
	}

	while (len) {
		if (x509_cert_from_der(&cert, &certlen, &p, &len) != 1
			|| x509_cert_get_subject(cert, certlen, &subject, &subject_len) != 1
			|| !subject || !subject_len) {
			error_print();
			return -1;
		}
		count++;
	}
	if (!count) {
		error_print();
		return -1;
	}

	if (!(owned = (uint8_t *)malloc(certslen))) {
		error_print();
		return -1;
	}
	memcpy(owned, certs, certslen);
	ctx->cacerts = owned;
	ctx->cacertslen = certslen;

	/*
	 * Server CertificateRequest needs CA-name advertisement metadata.
	 * Client trust validation only needs cacerts. Skipping the fixed-size
	 * advertisement buffers on clients allows large platform trust stores.
	 */
	if (!ctx->is_client) {
		if (tls_authorities_from_certs(ctx->ca_names, &ctx->ca_names_len,
				sizeof(ctx->ca_names), ctx->cacerts, ctx->cacertslen) != 1
			|| tls_trusted_authorities_from_ca_names(
				ctx->trusted_authorities, &ctx->trusted_authorities_len,
				sizeof(ctx->trusted_authorities),
				ctx->ca_names, ctx->ca_names_len) != 1) {
			free(ctx->cacerts);
			ctx->cacerts = NULL;
			ctx->cacertslen = 0;
			ctx->ca_names_len = 0;
			ctx->trusted_authorities_len = 0;
			error_print();
			return -1;
		}
	}

	ctx->verify_depth = depth;
	return 1;
}

int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth)
{
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_cert_c)
