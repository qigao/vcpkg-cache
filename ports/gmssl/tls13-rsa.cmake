# TLS 1.3 RSA-PSS server-authentication support.
# Verification-only: do not enable RSA private-key signing in GmSSL.

set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")
set(_gmssl_tls_trace_c "${SOURCE_PATH}/src/tls_trace.c")

# Advertise the TLS 1.3 RSA-PSS scheme when SHA-256 is enabled.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
const int tls13_signature_algorithms[] = {
	TLS_sig_sm2sig_sm3,
#if defined(ENABLE_SECP256R1) && defined(ENABLE_SHA2)
	TLS_sig_ecdsa_secp256r1_sha256,
#endif
};
]==]
[==[
const int tls13_signature_algorithms[] = {
	TLS_sig_sm2sig_sm3,
#if defined(ENABLE_SECP256R1) && defined(ENABLE_SHA2)
	TLS_sig_ecdsa_secp256r1_sha256,
#endif
#if defined(ENABLE_SHA2)
	TLS_sig_rsa_pss_rsae_sha256,
#endif
};
]==]
)

# A certificate's SubjectPublicKeyInfo selects a CertificateVerify signature
# family. RSA keys are not EC groups: match the RSA schemes explicitly.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	if (subject_public_key.algor != OID_ec_public_key) {
		error_print();
		return -1;
	}
	group_oid = subject_public_key.algor_param;

	for (i = 0; i < signature_algorithms_cnt; i++) {
		if (group_oid == tls_signature_scheme_group_oid(signature_algorithms[i])) {
			*first_matched_sig_alg = signature_algorithms[i];
			return 1;
		}
	}
]==]
[==[
	if (subject_public_key.algor == OID_rsa_encryption) {
		for (i = 0; i < signature_algorithms_cnt; i++) {
			switch (signature_algorithms[i]) {
			case TLS_sig_rsa_pss_rsae_sha256:
			case TLS_sig_rsa_pkcs1_sha256:
				*first_matched_sig_alg = signature_algorithms[i];
				return 1;
			}
		}
	} else if (subject_public_key.algor == OID_ec_public_key) {
		group_oid = subject_public_key.algor_param;
		for (i = 0; i < signature_algorithms_cnt; i++) {
			if (group_oid == tls_signature_scheme_group_oid(signature_algorithms[i])) {
				*first_matched_sig_alg = signature_algorithms[i];
				return 1;
			}
		}
	} else {
		error_print();
		return -1;
	}
]==]
)

# signature_algorithms_cert checks the certificate issuer's public-key family.
# Preserve EC behavior while allowing RSA issuers with no named-curve group.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
		if (subject_public_key.algor != OID_ec_public_key) {
			error_print();
			return -1;
		}
		group_oid = subject_public_key.algor_param;
		if (!(sig_alg = tls_signature_scheme_from_algorithm_and_group_oid(alg_oid, group_oid))) {
]==]
[==[
		if (subject_public_key.algor == OID_ec_public_key) {
			group_oid = subject_public_key.algor_param;
		} else if (subject_public_key.algor == OID_rsa_encryption) {
			group_oid = OID_undef;
		} else {
			error_print();
			return -1;
		}
		if (!(sig_alg = tls_signature_scheme_from_algorithm_and_group_oid(alg_oid, group_oid))) {
]==]
)

# Map an RSA/SHA-256 certificate signature to the TLS certificate-signature
# scheme. RSA-PSS CertificateVerify itself has no X.509 AlgorithmIdentifier
# requirement here.
gmssl_replace_once(
    "${_gmssl_tls_trace_c}"
[==[
int tls_signature_scheme_from_algorithm_and_group_oid(int alg_oid, int group_oid)
{
	if (alg_oid == OID_sm2sign_with_sm3 && group_oid == OID_sm2) {
		return TLS_sig_sm2sig_sm3;
	} else if (alg_oid == OID_ecdsa_with_sha256 && group_oid == OID_secp256r1) {
		return TLS_sig_ecdsa_secp256r1_sha256;
	}
	return 0;
}

int tls_signature_scheme_algorithm_oid(int sig_alg)
{
	switch (sig_alg) {
	case TLS_sig_sm2sig_sm3: return OID_sm2sign_with_sm3;
	case TLS_sig_ecdsa_secp256r1_sha256: return OID_ecdsa_with_sha256;
	}
	return 0;
}

int tls_signature_scheme_group_oid(int sig_alg)
{
	switch (sig_alg) {
	case TLS_sig_sm2sig_sm3: return OID_sm2;
	case TLS_sig_ecdsa_secp256r1_sha256: return OID_secp256r1;
	}
	return 0;
}
]==]
[==[
int tls_signature_scheme_from_algorithm_and_group_oid(int alg_oid, int group_oid)
{
	if (alg_oid == OID_sm2sign_with_sm3 && group_oid == OID_sm2) {
		return TLS_sig_sm2sig_sm3;
	} else if (alg_oid == OID_ecdsa_with_sha256 && group_oid == OID_secp256r1) {
		return TLS_sig_ecdsa_secp256r1_sha256;
	} else if (alg_oid == OID_rsasign_with_sha256 && group_oid == OID_undef) {
		return TLS_sig_rsa_pkcs1_sha256;
	}
	return 0;
}

int tls_signature_scheme_algorithm_oid(int sig_alg)
{
	switch (sig_alg) {
	case TLS_sig_sm2sig_sm3: return OID_sm2sign_with_sm3;
	case TLS_sig_ecdsa_secp256r1_sha256: return OID_ecdsa_with_sha256;
	case TLS_sig_rsa_pkcs1_sha256: return OID_rsasign_with_sha256;
	}
	return 0;
}

int tls_signature_scheme_group_oid(int sig_alg)
{
	switch (sig_alg) {
	case TLS_sig_sm2sig_sm3: return OID_sm2;
	case TLS_sig_ecdsa_secp256r1_sha256: return OID_secp256r1;
	case TLS_sig_rsa_pkcs1_sha256:
	case TLS_sig_rsa_pss_rsae_sha256:
		return OID_undef;
	}
	return 0;
}
]==]
)

# Permit RSA-PSS in the verification-only TLS 1.3 CertificateVerify path.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		if (public_key->algor != OID_ec_public_key
			&& public_key->algor_param != OID_secp256r1) {
			error_print();
			return -1;
		}
		if (tbs_dgst_ctx->digest->oid != OID_sha256) {
			error_print();
			return -1;
		}
		break;

	default:
]==]
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		if (public_key->algor != OID_ec_public_key
			&& public_key->algor_param != OID_secp256r1) {
			error_print();
			return -1;
		}
		if (tbs_dgst_ctx->digest->oid != OID_sha256) {
			error_print();
			return -1;
		}
		break;

	case TLS_sig_rsa_pss_rsae_sha256:
		if (public_key->algor != OID_rsa_encryption) {
			error_print();
			return -1;
		}
		break;

	default:
]==]
)

gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	if (digest_finish(&dgst_ctx, dgst, &dgstlen) != 1) {
		error_print();
		return -1;
	}

	/*
	format_print(stderr, 0, 0, "verify_certificate_verify\n");
]==]
[==[
	if (digest_finish(&dgst_ctx, dgst, &dgstlen) != 1) {
		error_print();
		return -1;
	}

	if (sig_alg == TLS_sig_rsa_pss_rsae_sha256) {
		DIGEST_CTX rsa_dgst_ctx;
		uint8_t rsa_dgst[64];
		size_t rsa_dgstlen = 0;

		if (digest_init(&rsa_dgst_ctx, DIGEST_sha256()) != 1
			|| digest_update(&rsa_dgst_ctx, prefix, sizeof(prefix)) != 1
			|| digest_update(&rsa_dgst_ctx, context_str_and_zero, context_str_and_zero_len) != 1
			|| digest_update(&rsa_dgst_ctx, dgst, dgstlen) != 1
			|| digest_finish(&rsa_dgst_ctx, rsa_dgst, &rsa_dgstlen) != 1) {
			gmssl_secure_clear(&rsa_dgst_ctx, sizeof(rsa_dgst_ctx));
			gmssl_secure_clear(rsa_dgst, sizeof(rsa_dgst));
			error_print();
			return -1;
		}
		if (rsa_dgstlen != 32) {
			gmssl_secure_clear(&rsa_dgst_ctx, sizeof(rsa_dgst_ctx));
			gmssl_secure_clear(rsa_dgst, sizeof(rsa_dgst));
			error_print();
			return -1;
		}
		ret = rsa_verify_pss_sha256(&public_key->u.rsa_public_key,
			rsa_dgst, sig, siglen);
		gmssl_secure_clear(&rsa_dgst_ctx, sizeof(rsa_dgst_ctx));
		gmssl_secure_clear(rsa_dgst, sizeof(rsa_dgst));
		if (ret < 0) {
			error_print();
			return -1;
		}
		if (ret != 1) {
			error_print();
		}
		return ret;
	}

	/*
	format_print(stderr, 0, 0, "verify_certificate_verify\n");
]==]
)

unset(_gmssl_tls13_c)
unset(_gmssl_tls_trace_c)
