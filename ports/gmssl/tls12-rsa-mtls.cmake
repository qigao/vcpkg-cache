# TLS 1.2 RSA mutual-authentication support.
# Adds RSA certificate types and exact CertificateVerify signing/verification.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_cert_c "${SOURCE_PATH}/src/tls_cert.c")
set(_gmssl_tls12_c "${SOURCE_PATH}/src/tls12.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_cert_types_has_ecdsa_sign(const uint8_t *types, size_t types_len);
]==]
[==[
int tls_cert_types_has_rsa_sign(const uint8_t *types, size_t types_len);
int tls_cert_types_has_ecdsa_sign(const uint8_t *types, size_t types_len);
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
int tls_cert_types_has_ecdsa_sign(const uint8_t *types, size_t types_len)
{
	return 1;
}
]==]
[==[
static int tls_cert_types_has(const uint8_t *types, size_t types_len, uint8_t wanted)
{
	size_t i;
	if (!types || !types_len) {
		return 0;
	}
	for (i = 0; i < types_len; i++) {
		if (types[i] == wanted) return 1;
	}
	return 0;
}

int tls_cert_types_has_rsa_sign(const uint8_t *types, size_t types_len)
{
	return tls_cert_types_has(types, types_len, TLS_cert_type_rsa_sign);
}

int tls_cert_types_has_ecdsa_sign(const uint8_t *types, size_t types_len)
{
	return tls_cert_types_has(types, types_len, TLS_cert_type_ecdsa_sign);
}
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	const uint8_t cert_types[] = { TLS_cert_type_ecdsa_sign };
]==]
[==[
	const uint8_t cert_types[] = {
		TLS_cert_type_rsa_sign,
		TLS_cert_type_ecdsa_sign
	};
]==]
)

# Validate CertificateRequest certificate_types against the actual configured
# client identity instead of accepting an ECDSA-only stub.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	const uint8_t *client_cert;
	size_t client_cert_len;
	int client_sig_alg;
]==]
[==[
	const uint8_t *client_cert;
	size_t client_cert_len;
	X509_KEY client_public_key;
	int client_sig_alg;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if (tls_cert_types_has_ecdsa_sign(cert_types, cert_types_len) != 1
		|| tls_authorities_issued_certificate(ca_names, ca_names_len, conn->client_certs, conn->client_certs_len) != 1) {
		error_print();
		tls_send_alert(conn, TLS_alert_unsupported_certificate);
		return -1;
	}
	if (x509_certs_get_cert_by_index(conn->client_certs, conn->client_certs_len,
		0, &client_cert, &client_cert_len) != 1) {
]==]
[==[
	if (tls_authorities_issued_certificate(ca_names, ca_names_len,
		conn->client_certs, conn->client_certs_len) != 1) {
		error_print();
		tls_send_alert(conn, TLS_alert_unsupported_certificate);
		return -1;
	}
	if (x509_certs_get_cert_by_index(conn->client_certs, conn->client_certs_len,
		0, &client_cert, &client_cert_len) != 1) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if ((ret = tls_cert_match_signature_algorithms(client_cert, client_cert_len,
		common_sig_algs, common_sig_algs_cnt, &client_sig_alg)) < 0) {
]==]
[==[
	if (x509_cert_get_subject_public_key(client_cert, client_cert_len,
		&client_public_key) != 1) {
		error_print();
		tls_send_alert(conn, TLS_alert_bad_certificate);
		return -1;
	}
	if ((client_public_key.algor == OID_rsa_encryption
			&& tls_cert_types_has_rsa_sign(cert_types, cert_types_len) != 1)
		|| (client_public_key.algor == OID_ec_public_key
			&& tls_cert_types_has_ecdsa_sign(cert_types, cert_types_len) != 1)
		|| (client_public_key.algor != OID_rsa_encryption
			&& client_public_key.algor != OID_ec_public_key)) {
		error_print();
		tls_send_alert(conn, TLS_alert_unsupported_certificate);
		return -1;
	}
	if ((ret = tls_cert_match_signature_algorithms(client_cert, client_cert_len,
		common_sig_algs, common_sig_algs_cnt, &client_sig_alg)) < 0) {
]==]
)

# RSA CertificateVerify is modulus-sized.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
int tls_send_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	uint8_t sig[SM2_MAX_SIGNATURE_SIZE];
]==]
[==[
int tls_send_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	uint8_t sig[RSA_MAX_MODULUS_SIZE];
]==]
)

# Verify the exact TLS signature scheme against the presented client key.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if (client_sign_key.algor != OID_ec_public_key) {
		error_print();
		tls_send_alert(conn, TLS_alert_bad_certificate);
		return -1;
	}
	if (client_sign_key.algor_param == OID_sm2) {
		signer_id = (uint8_t *)SM2_DEFAULT_ID;
		signer_idlen = SM2_DEFAULT_ID_LENGTH;
	}
	if (x509_verify_init(&sign_ctx, &client_sign_key, signer_id, signer_idlen, sig, siglen) != 1
]==]
[==[
	if (client_sign_key.algor == OID_rsa_encryption) {
		if (sig_alg != TLS_sig_rsa_pkcs1_sha256) {
			error_print();
			tls_send_alert(conn, TLS_alert_unsupported_certificate);
			return -1;
		}
	} else if (client_sign_key.algor == OID_ec_public_key) {
		if (client_sign_key.algor_param == OID_sm2) {
			signer_id = (uint8_t *)SM2_DEFAULT_ID;
			signer_idlen = SM2_DEFAULT_ID_LENGTH;
		}
	} else {
		error_print();
		tls_send_alert(conn, TLS_alert_bad_certificate);
		return -1;
	}
	if (x509_verify_init_ex(&sign_ctx, &client_sign_key,
		tls_signature_scheme_algorithm_oid(sig_alg),
		signer_id, signer_idlen, sig, siglen) != 1
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_cert_c)
unset(_gmssl_tls12_c)
