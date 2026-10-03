# TLS 1.2 ECDHE_RSA client authentication support.
# Verification-only: RSA private-key signing remains intentionally disabled.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")
set(_gmssl_tls12_c "${SOURCE_PATH}/src/tls12.c")
set(_gmssl_tls_vrf_c "${SOURCE_PATH}/src/tls_vrf.c")
set(_gmssl_tls_trace_c "${SOURCE_PATH}/src/tls_trace.c")

# RFC 5289 TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256.
gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
	TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256 = 0xc02b,
	TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm = 0xc0ac,
]==]
[==[
	TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256 = 0xc02b,
	TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256 = 0xc02f,
	TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm = 0xc0ac,
]==]
)

# AES-128-GCM/SHA-256 record/key schedule is identical regardless of whether
# ServerKeyExchange is authenticated by ECDSA or RSA.
vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:"
    "case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:\n\tcase TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:"
)

# Trace/name support is required by tools and configuration.
gmssl_replace_once(
    "${_gmssl_tls_trace_c}"
[==[
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256: return "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256";
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm: return "TLS_ECDHE_ECDSA_WITH_AES_128_CCM";
]==]
[==[
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256: return "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256";
	case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256: return "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256";
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm: return "TLS_ECDHE_ECDSA_WITH_AES_128_CCM";
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_trace_c}"
[==[
	} else if (!strcmp(name, "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256")) {
		return TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256;
	} else if (!strcmp(name, "TLS_ECDHE_ECDSA_WITH_AES_128_CCM")) {
]==]
[==[
	} else if (!strcmp(name, "TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256")) {
		return TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256;
	} else if (!strcmp(name, "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256")) {
		return TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256;
	} else if (!strcmp(name, "TLS_ECDHE_ECDSA_WITH_AES_128_CCM")) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_trace_c}"
[==[
	if (!strcmp(name, "ecdsa_secp256r1_sha256")) {
		return TLS_sig_ecdsa_secp256r1_sha256;
	} else if (!strcmp(name, "sm2sig_sm3")) {
]==]
[==[
	if (!strcmp(name, "ecdsa_secp256r1_sha256")) {
		return TLS_sig_ecdsa_secp256r1_sha256;
	} else if (!strcmp(name, "rsa_pkcs1_sha256")) {
		return TLS_sig_rsa_pkcs1_sha256;
	} else if (!strcmp(name, "rsa_pss_rsae_sha256")) {
		return TLS_sig_rsa_pss_rsae_sha256;
	} else if (!strcmp(name, "sm2sig_sm3")) {
]==]
)

# ServerKeyExchange pretty-printing follows the same ECDHE wire structure.
gmssl_replace_once(
    "${_gmssl_tls_trace_c}"
[==[
	case TLS_cipher_ecdhe_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		if (tls_server_key_exchange_ecdhe_print(fp, data, datalen, fmt, ind) != 1) {
]==]
[==[
	case TLS_cipher_ecdhe_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:
		if (tls_server_key_exchange_ecdhe_print(fp, data, datalen, fmt, ind) != 1) {
]==]
)

# Advertise the RSA signature scheme and ECDHE_RSA cipher suite for TLS 1.2.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
const int tls12_signature_algorithms[] = {
	TLS_sig_sm2sig_sm3,
#if defined(ENABLE_SECP256R1) && defined(ENABLE_SHA2)
	TLS_sig_ecdsa_secp256r1_sha256,
#endif
};
]==]
[==[
const int tls12_signature_algorithms[] = {
	TLS_sig_sm2sig_sm3,
#if defined(ENABLE_SECP256R1) && defined(ENABLE_SHA2)
	TLS_sig_ecdsa_secp256r1_sha256,
#endif
#if defined(ENABLE_SHA2)
	TLS_sig_rsa_pkcs1_sha256,
#endif
};
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256,
	TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256,
#ifdef ENABLE_AES_CCM
]==]
[==[
	TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256,
	TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256,
	TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256,
#ifdef ENABLE_AES_CCM
]==]
)

# ECDHE_RSA authenticates with RSA but still uses secp256r1 for ephemeral ECDH.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	case TLS_curve_secp256r1:
		switch (cipher_suite) {
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
]==]
[==[
	case TLS_curve_secp256r1:
		switch (cipher_suite) {
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		switch (cipher_suite) {
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
			break;
		default:
			error_print();
			return -1;
		}
		break;
	default:
]==]
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		switch (cipher_suite) {
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
			break;
		default:
			error_print();
			return -1;
		}
		break;
	case TLS_sig_rsa_pkcs1_sha256:
		if (cipher_suite != TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256) {
			error_print();
			return -1;
		}
		break;
	default:
]==]
)

# Internal matching used by TLS 1.2 server parameter selection and validation.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		switch (cipher_suite) {
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
			return 1;
		}
		break;
	}
	return 0;
}
]==]
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		switch (cipher_suite) {
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
			return 1;
		}
		break;
	case TLS_sig_rsa_pkcs1_sha256:
		return cipher_suite == TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256;
	}
	return 0;
}
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
		return group == TLS_curve_secp256r1;
]==]
[==[
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
		return group == TLS_curve_secp256r1;
]==]
)

# Verify TLS 1.2 ServerKeyExchange using the RSA leaf key. x509_verify_init()
# now routes rsaEncryption + SHA-256 to the strict PKCS#1 verifier.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		if (server_sign_key.algor != OID_ec_public_key
			|| server_sign_key.algor_param != OID_secp256r1) {
			error_print();
			tls_send_alert(conn, TLS_alert_bad_certificate);
			return -1;
		}
		break;
	default:
]==]
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		if (server_sign_key.algor != OID_ec_public_key
			|| server_sign_key.algor_param != OID_secp256r1) {
			error_print();
			tls_send_alert(conn, TLS_alert_bad_certificate);
			return -1;
		}
		break;
	case TLS_sig_rsa_pkcs1_sha256:
		if (server_sign_key.algor != OID_rsa_encryption) {
			error_print();
			tls_send_alert(conn, TLS_alert_bad_certificate);
			return -1;
		}
		break;
	default:
]==]
)

# The received signature must have been offered by this client.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if (tls_signature_scheme_match_cipher_suite(sig_alg, conn->cipher_suite) != 1) {
		error_print();
		tls_send_alert(conn, TLS_alert_illegal_parameter);
		return -1;
	}
]==]
[==[
	if ((conn->ctx->signature_algorithms_cnt
			&& !tls_type_is_in_list(sig_alg,
				conn->ctx->signature_algorithms, conn->ctx->signature_algorithms_cnt))
		|| tls_signature_scheme_match_cipher_suite(sig_alg, conn->cipher_suite) != 1) {
		error_print();
		tls_send_alert(conn, TLS_alert_illegal_parameter);
		return -1;
	}
]==]
)

# TLS certificate policy: RSA certificate authentication is independent of the
# ephemeral ECDHE named group. Represent "no certificate group" as zero.
gmssl_replace_once(
    "${_gmssl_tls_vrf_c}"
[==[
	if (public_key.algor != OID_ec_public_key) {
		error_print();
		return -1;
	}
	if ((*group = tls_named_curve_from_oid(public_key.algor_param)) == 0) {
		error_print();
		return -1;
	}
	return 1;
]==]
[==[
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
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_vrf_c}"
[==[
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
		return cert_group == TLS_curve_secp256r1;
	default:
]==]
[==[
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
		return cert_group == TLS_curve_secp256r1;
	case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:
		return cert_group == 0;
	default:
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_vrf_c}"
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		switch (cipher_suite) {
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
			return 1;
		}
		break;
	}
	return 0;
}
]==]
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		switch (cipher_suite) {
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
			return 1;
		}
		break;
	case TLS_sig_rsa_pkcs1_sha256:
		return cipher_suite == TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256;
	}
	return 0;
}
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_vrf_c}"
[==[
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
		return TLS_sig_ecdsa_secp256r1_sha256;
	default:
]==]
[==[
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_cbc_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_ccm:
		return TLS_sig_ecdsa_secp256r1_sha256;
	case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:
		return TLS_sig_rsa_pkcs1_sha256;
	default:
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_vrf_c}"
[==[
		if (supported_groups && supported_groups_cnt) {
			if (!tls_type_is_in_list(cert_group, supported_groups, supported_groups_cnt)) {
				error_print();
				tls_cert_verify_set_result(verify_result, X509_verify_err_tls_extensions);
				return 0;
			}
		}
]==]
[==[
		if (cert_group && supported_groups && supported_groups_cnt) {
			if (!tls_type_is_in_list(cert_group, supported_groups, supported_groups_cnt)) {
				error_print();
				tls_cert_verify_set_result(verify_result, X509_verify_err_tls_extensions);
				return 0;
			}
		}
]==]
)


# The handshake key schedule already shares the AES-GCM path. Application-data
# record dispatch must also recognize the ECDHE_RSA suite explicitly.
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_record_encrypt(int cipher_suite,
	const HMAC_CTX *hmac_ctx, const BLOCK_CIPHER_KEY *key, const uint8_t fixed_iv[4],
	const uint8_t seq_num[8], const uint8_t *in, size_t inlen,
	uint8_t *out, size_t *outlen)
{
	switch (cipher_suite) {
	case TLS_cipher_ecc_sm4_cbc_sm3:
]==]
[==[
int tls_record_encrypt(int cipher_suite,
	const HMAC_CTX *hmac_ctx, const BLOCK_CIPHER_KEY *key, const uint8_t fixed_iv[4],
	const uint8_t seq_num[8], const uint8_t *in, size_t inlen,
	uint8_t *out, size_t *outlen)
{
	switch (cipher_suite) {
	case TLS_cipher_ecc_sm4_cbc_sm3:
]==]
)
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	case TLS_cipher_ecc_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		if (tls_gcm_encrypt(key, fixed_iv, seq_num, in,
]==]
[==[
	case TLS_cipher_ecc_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:
		if (tls_gcm_encrypt(key, fixed_iv, seq_num, in,
]==]
)
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_record_decrypt(int cipher_suite, const HMAC_CTX *hmac_ctx,
	const BLOCK_CIPHER_KEY *key, const uint8_t fixed_iv[4],
	const uint8_t seq_num[8], const uint8_t *in, size_t inlen,
	uint8_t *out, size_t *outlen)
{
	switch (cipher_suite) {
	case TLS_cipher_ecc_sm4_cbc_sm3:
]==]
[==[
int tls_record_decrypt(int cipher_suite, const HMAC_CTX *hmac_ctx,
	const BLOCK_CIPHER_KEY *key, const uint8_t fixed_iv[4],
	const uint8_t seq_num[8], const uint8_t *in, size_t inlen,
	uint8_t *out, size_t *outlen)
{
	switch (cipher_suite) {
	case TLS_cipher_ecc_sm4_cbc_sm3:
]==]
)
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	case TLS_cipher_ecc_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		if (tls_gcm_decrypt(key, fixed_iv, seq_num, in,
]==]
[==[
	case TLS_cipher_ecc_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_sm4_gcm_sm3:
	case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
	case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:
		if (tls_gcm_decrypt(key, fixed_iv, seq_num, in,
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
unset(_gmssl_tls12_c)
unset(_gmssl_tls_vrf_c)
unset(_gmssl_tls_trace_c)
