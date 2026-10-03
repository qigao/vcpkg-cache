# TLS 1.3 RSA-PSS signing for server identities and mTLS client identities.
# Depends on the bounded RSA private identity sidecar in X509_KEY.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")

# RSA-4096 signatures require 512 bytes; keep one bounded TLS-wide cap.
gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
#define TLS_MAX_SIGNATURE_SIZE	SM2_MAX_SIGNATURE_SIZE
]==]
[==[
#define TLS_MAX_SIGNATURE_SIZE	RSA_MAX_MODULUS_SIZE
]==]
)

# Permit RSA-PSS signing with an RSA private identity.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		if (sign_key->algor != OID_ec_public_key
			&& sign_key->algor_param != OID_secp256r1) {
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
		if (sign_key->algor != OID_ec_public_key
			&& sign_key->algor_param != OID_secp256r1) {
			error_print();
			return -1;
		}
		if (tbs_dgst_ctx->digest->oid != OID_sha256) {
			error_print();
			return -1;
		}
		break;

	case TLS_sig_rsa_pss_rsae_sha256:
		if (sign_key->algor != OID_rsa_encryption
			|| !sign_key->has_private_key
			|| tbs_dgst_ctx->digest->oid != OID_sha256) {
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

	if (x509_sign_init(&sign_ctx, sign_key, signer_id, signer_id_len) !=  1
]==]
[==[
	if (digest_finish(&dgst_ctx, dgst, &dgstlen) != 1) {
		error_print();
		return -1;
	}

	if (sig_alg == TLS_sig_rsa_pss_rsae_sha256) {
		DIGEST_CTX rsa_dgst_ctx;
		uint8_t rsa_dgst[SHA256_DIGEST_SIZE];
		size_t rsa_dgstlen = 0;
		int ret;

		if (digest_init(&rsa_dgst_ctx, DIGEST_sha256()) != 1
			|| digest_update(&rsa_dgst_ctx, prefix, sizeof(prefix)) != 1
			|| digest_update(&rsa_dgst_ctx, context_str_and_zero, context_str_and_zero_len) != 1
			|| digest_update(&rsa_dgst_ctx, dgst, dgstlen) != 1
			|| digest_finish(&rsa_dgst_ctx, rsa_dgst, &rsa_dgstlen) != 1
			|| rsa_dgstlen != SHA256_DIGEST_SIZE) {
			gmssl_secure_clear(&rsa_dgst_ctx, sizeof(rsa_dgst_ctx));
			gmssl_secure_clear(rsa_dgst, sizeof(rsa_dgst));
			error_print();
			return -1;
		}
		ret = rsa_sign_pss_sha256(&sign_key->rsa_private_key,
			rsa_dgst, sig, TLS_MAX_SIGNATURE_SIZE, siglen);
		gmssl_secure_clear(&rsa_dgst_ctx, sizeof(rsa_dgst_ctx));
		gmssl_secure_clear(rsa_dgst, sizeof(rsa_dgst));
		if (ret != 1) {
			error_print();
			return -1;
		}
		return 1;
	}

	if (x509_sign_init(&sign_ctx, sign_key, signer_id, signer_id_len) !=  1
]==]
)

# Use the TLS-wide bounded signature cap in both client and server CertificateVerify.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
		uint8_t sig[256];
]==]
[==[
		uint8_t sig[TLS_MAX_SIGNATURE_SIZE];
]==]
)

gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
		uint8_t sig[SM2_MAX_SIGNATURE_SIZE];
]==]
[==[
		uint8_t sig[TLS_MAX_SIGNATURE_SIZE];
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls13_c)
