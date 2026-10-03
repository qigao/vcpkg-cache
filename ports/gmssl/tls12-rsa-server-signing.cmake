# TLS 1.2 ECDHE_RSA server identity/signing support.

set(_gmssl_tls12_c "${SOURCE_PATH}/src/tls12.c")

# RSA certificate authentication has no EC certificate group.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
static int tls12_cert_chain_get_end_entity_group(const uint8_t *cert_chain, size_t cert_chain_len, int *group)
{
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if (!cert_chain || !cert_chain_len || !group) {
		error_print();
		return -1;
	}
	if (x509_certs_get_cert_by_index(cert_chain, cert_chain_len, 0, &cert, &certlen) != 1
		|| x509_cert_get_subject_public_key(cert, certlen, &public_key) != 1) {
		error_print();
		return -1;
	}
	if (public_key.algor != OID_ec_public_key) {
		error_print();
		return -1;
	}
	if ((*group = tls_named_curve_from_oid(public_key.algor_param)) == 0) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
[==[
static int tls12_cert_chain_get_end_entity_group(const uint8_t *cert_chain, size_t cert_chain_len, int *group)
{
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if (!cert_chain || !cert_chain_len || !group) {
		error_print();
		return -1;
	}
	if (x509_certs_get_cert_by_index(cert_chain, cert_chain_len, 0, &cert, &certlen) != 1
		|| x509_cert_get_subject_public_key(cert, certlen, &public_key) != 1) {
		error_print();
		return -1;
	}
	if (public_key.algor == OID_rsa_encryption) {
		*group = 0;
		return 1;
	}
	if (public_key.algor != OID_ec_public_key) {
		error_print();
		return -1;
	}
	if ((*group = tls_named_curve_from_oid(public_key.algor_param)) == 0) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
)

# Keep RSA selection local to tls12_select_parameters(); generic EC helpers
# continue to describe real named groups only.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
			if (!tls12_cipher_suite_match_cert_group(cipher_suite, cert_group)) {
				continue;
			}
]==]
[==[
			if (cipher_suite == TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256) {
				if (cert_group != 0) {
					continue;
				}
			} else if (!tls12_cipher_suite_match_cert_group(cipher_suite, cert_group)) {
				continue;
			}
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
				if (!tls12_signature_scheme_match_cert_group(sig_alg, cert_group)) {
					continue;
				}
]==]
[==[
				if (sig_alg == TLS_sig_rsa_pkcs1_sha256) {
					if (cert_group != 0) {
						continue;
					}
				} else if (!tls12_signature_scheme_match_cert_group(sig_alg, cert_group)) {
					continue;
				}
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		if (!tls_type_is_in_list(cert_group, common_supported_groups, common_supported_groups_cnt)) {
			continue;
		}
]==]
[==[
		if (cert_group
			&& !tls_type_is_in_list(cert_group,
				common_supported_groups, common_supported_groups_cnt)) {
			continue;
		}
]==]
)

# RSA ServerKeyExchange signatures are modulus-sized.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		uint8_t sig[X509_SIGNATURE_MAX_SIZE];
		size_t siglen;
]==]
[==[
		uint8_t sig[RSA_MAX_MODULUS_SIZE];
		size_t siglen;
]==]
)

unset(_gmssl_tls12_c)
