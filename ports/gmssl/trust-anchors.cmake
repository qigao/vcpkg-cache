# Trust-anchor APIs required by Salts/CNet platform trust-store integration.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_cert_c "${SOURCE_PATH}/src/tls_cert.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
]==]
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
int tls_ctx_set_ca_certificates_der(TLS_CTX *ctx,
	const uint8_t *cacerts, size_t cacertslen, int depth);
]==]
)

# Client trust bundles can contain hundreds of roots. ca_names/trusted_authorities
# are CertificateRequest/trusted_ca_keys presentation data and must not bound
# the client verification store to the fixed 512-byte name buffer.
gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
	// 在读取CA证书的时候，提取了证书的名字
	if (tls_authorities_from_certs(ctx->ca_names, &ctx->ca_names_len, sizeof(ctx->ca_names),
		ctx->cacerts, ctx->cacertslen) != 1) {
		error_print();
		return -1;
	}
	if (tls_trusted_authorities_from_ca_names(ctx->trusted_authorities, &ctx->trusted_authorities_len,
		sizeof(ctx->trusted_authorities), ctx->ca_names, ctx->ca_names_len) != 1) {
		error_print();
		return -1;
	}

	ctx->verify_depth = depth;
	return 1;
}
]==]
[==[
	// Server-side CertificateRequest/trusted_ca_keys may expose authority names.
	// Client-side verification needs the full trust store, not a 512-byte name list.
	if (!ctx->is_client) {
		if (tls_authorities_from_certs(ctx->ca_names, &ctx->ca_names_len, sizeof(ctx->ca_names),
			ctx->cacerts, ctx->cacertslen) != 1) {
			error_print();
			return -1;
		}
		if (tls_trusted_authorities_from_ca_names(
			ctx->trusted_authorities, &ctx->trusted_authorities_len,
			sizeof(ctx->trusted_authorities), ctx->ca_names, ctx->ca_names_len) != 1) {
			error_print();
			return -1;
		}
	}

	ctx->verify_depth = depth;
	return 1;
}

int tls_ctx_set_ca_certificates_der(TLS_CTX *ctx,
	const uint8_t *cacerts, size_t cacertslen, int depth)
{
	uint8_t *copy = NULL;
	size_t certs_cnt = 0;

	if (!ctx || !cacerts || !cacertslen) {
		error_print();
		return -1;
	}
	if (depth < 0 || depth > TLS_MAX_VERIFY_DEPTH
		|| !tls_protocol_name(ctx->protocol)
		|| ctx->cacerts) {
		error_print();
		return -1;
	}
	if (x509_certs_get_count(cacerts, cacertslen, &certs_cnt) != 1
		|| certs_cnt == 0) {
		error_print();
		return -1;
	}
	copy = (uint8_t *)malloc(cacertslen);
	if (!copy) {
		error_print();
		return -1;
	}
	memcpy(copy, cacerts, cacertslen);
	ctx->cacerts = copy;
	ctx->cacertslen = cacertslen;

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
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_cert_c)
