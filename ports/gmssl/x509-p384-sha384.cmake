# Verify-only P-384 / ECDSA-SHA384 backport for X.509 issuing CA chains.
# Source: guanzhi/GmSSL 24ae482701a7b124826c382fffc55c19f76d475d (Apache-2.0), trimmed to verifier.
# No P-384 TLS key agreement, no new TLS scheduler, no OpenSSL fallback.

configure_file("${CMAKE_CURRENT_LIST_DIR}/backports/secp384r1_verify.c"
               "${SOURCE_PATH}/src/secp384r1.c" COPYONLY)
configure_file("${CMAKE_CURRENT_LIST_DIR}/backports/secp384r1_verify.h"
               "${SOURCE_PATH}/include/gmssl/secp384r1.h" COPYONLY)

set(_gmssl_p384_cmake "${SOURCE_PATH}/CMakeLists.txt")
set(_gmssl_p384_h "${SOURCE_PATH}/include/gmssl/x509_key.h")
set(_gmssl_p384_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_p384_cmake}"
[==[
	list(APPEND src src/bn.c src/secp256r1.c src/secp256r1_key.c src/ecdsa.c src/ecdh.c)
]==]
[==[
	add_definitions(-DENABLE_SECP384R1)
	list(APPEND src src/bn.c src/secp256r1.c src/secp256r1_key.c src/ecdsa.c src/ecdh.c src/secp384r1.c)
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_h}"
[==[
#include <gmssl/ecdsa.h>
#endif
]==]
[==[
#include <gmssl/ecdsa.h>
#endif
#ifdef ENABLE_SECP384R1
#include <gmssl/secp384r1.h>
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_h}"
[==[
		SECP256R1_KEY secp256r1_key;
#endif
]==]
[==[
		SECP256R1_KEY secp256r1_key;
#endif
#ifdef ENABLE_SECP384R1
		SECP384R1_KEY secp384r1_key;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_h}"
[==[
		ECDSA_SIGN_CTX ecdsa_sign_ctx;
#endif
]==]
[==[
		ECDSA_SIGN_CTX ecdsa_sign_ctx;
#endif
#ifdef ENABLE_SECP384R1
		SECP384R1_ECDSA_SIGN_CTX ecdsa_p384_verify_ctx;
		SHA384_CTX ecdsa_p256_sha384_ctx;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_secp256r1:
			if (secp256r1_public_key_to_bytes(&key->u.secp256r1_key, out, outlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
]==]
[==[
		case OID_secp256r1:
			if (secp256r1_public_key_to_bytes(&key->u.secp256r1_key, out, outlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
#ifdef ENABLE_SECP384R1
		case OID_secp384r1:
			if (secp384r1_public_key_to_bytes(&key->u.secp384r1_key, out, outlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_secp256r1:
			if (secp256r1_public_key_from_bytes(&key->u.secp256r1_key, in, inlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
]==]
[==[
		case OID_secp256r1:
			if (secp256r1_public_key_from_bytes(&key->u.secp256r1_key, in, inlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
#ifdef ENABLE_SECP384R1
		case OID_secp384r1:
			if (secp384r1_public_key_from_bytes(&key->u.secp384r1_key, in, inlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		} else if (key->algor_param == OID_secp256r1) {
			if ((ret = secp256r1_public_key_equ(&key->u.secp256r1_key, &pub->u.secp256r1_key)) != 1) {
				error_print();
				return ret;
			}
#endif
]==]
[==[
		} else if (key->algor_param == OID_secp256r1) {
			if ((ret = secp256r1_public_key_equ(&key->u.secp256r1_key, &pub->u.secp256r1_key)) != 1) {
				error_print();
				return ret;
			}
#endif
#ifdef ENABLE_SECP384R1
		} else if (key->algor_param == OID_secp384r1) {
			if ((ret = secp384r1_public_key_equ(&key->u.secp384r1_key, &pub->u.secp384r1_key)) != 1) {
				error_print();
				return ret;
			}
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
	if (key->algor == OID_rsa_encryption) {
		return algor == OID_rsasign_with_sha256 ? 1 : 0;
	}
	if (x509_key_get_sign_algor(key, &default_algor) != 1)
]==]
[==[
	if (key->algor == OID_rsa_encryption) {
		return algor == OID_rsasign_with_sha256 ? 1 : 0;
	}
#ifdef ENABLE_SECP384R1
	if (key->algor == OID_ec_public_key && key->algor_param == OID_secp384r1)
		return algor == OID_ecdsa_with_sha384 ? 1 : 0;
	if (key->algor == OID_ec_public_key && key->algor_param == OID_secp256r1)
		return algor == OID_ecdsa_with_sha256 || algor == OID_ecdsa_with_sha384 ? 1 : 0;
#endif
	if (x509_key_get_sign_algor(key, &default_algor) != 1)
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_secp256r1:
			*algor = OID_ecdsa_with_sha256;
			break;
#endif
]==]
[==[
		case OID_secp256r1:
			*algor = OID_ecdsa_with_sha256;
			break;
#endif
#ifdef ENABLE_SECP384R1
		case OID_secp384r1:
			*algor = OID_ecdsa_with_sha384;
			break;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_secp256r1:
			if (ecdsa_verify_init(&ctx->u.ecdsa_sign_ctx, &key->u.secp256r1_key, sig, siglen) != 1) {
				error_print();
				return -1;
			}
			ctx->sign_algor = OID_ecdsa_with_sha256;
			break;
#endif
]==]
[==[
		case OID_secp256r1:
#ifdef ENABLE_SECP384R1
			if (sign_algor == OID_ecdsa_with_sha384) {
				sha384_init(&ctx->u.ecdsa_p256_sha384_ctx);
				ctx->key = *key;
				ctx->sig = sig;
				ctx->siglen = siglen;
				ctx->sign_algor = OID_ecdsa_with_sha384;
				break;
			}
#endif
			if (ecdsa_verify_init(&ctx->u.ecdsa_sign_ctx, &key->u.secp256r1_key, sig, siglen) != 1) {
				error_print();
				return -1;
			}
			ctx->sign_algor = OID_ecdsa_with_sha256;
			break;
#endif
#ifdef ENABLE_SECP384R1
		case OID_secp384r1:
			if (secp384r1_ecdsa_verify_init(&ctx->u.ecdsa_p384_verify_ctx,
				&key->u.secp384r1_key, DIGEST_sha384(), sig, siglen) != 1)
				return -1;
			ctx->key = *key;
			ctx->sign_algor = OID_ecdsa_with_sha384;
			break;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
]==]
[==[
int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	switch (ctx->sign_algor) {
#ifdef ENABLE_SECP384R1
	case OID_ecdsa_with_sha384:
		if (ctx->key.algor_param == OID_secp384r1) {
			if (secp384r1_ecdsa_verify_update(&ctx->u.ecdsa_p384_verify_ctx, data, datalen) != 1)
				return -1;
		} else if (ctx->key.algor_param == OID_secp256r1) {
			sha384_update(&ctx->u.ecdsa_p256_sha384_ctx, data, datalen);
		} else return -1;
		break;
#endif
	case OID_rsasign_with_sha256:
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
int x509_verify_finish(X509_SIGN_CTX *ctx)
{
	int ret;
	const char *id;
	size_t idlen;

	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
]==]
[==[
int x509_verify_finish(X509_SIGN_CTX *ctx)
{
	int ret;
	const char *id;
	size_t idlen;

	switch (ctx->sign_algor) {
#ifdef ENABLE_SECP384R1
	case OID_ecdsa_with_sha384:
		if (ctx->key.algor_param == OID_secp384r1) {
			ret = secp384r1_ecdsa_verify_finish(&ctx->u.ecdsa_p384_verify_ctx);
		} else if (ctx->key.algor_param == OID_secp256r1) {
			uint8_t dgst[SHA384_DIGEST_SIZE];
			sha384_finish(&ctx->u.ecdsa_p256_sha384_ctx, dgst);
			/* FIPS 186 ECDSA: leftmost 256 bits of SHA-384 digest for P-256. */
			ret = ecdsa_verify(&ctx->key.u.secp256r1_key, dgst, ctx->sig, ctx->siglen);
			gmssl_secure_clear(dgst, sizeof(dgst));
		} else return -1;
		if (ret != 1) return ret < 0 ? -1 : 0;
		break;
#endif
	case OID_rsasign_with_sha256:
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
int x509_verify(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	int ret;

	if (!ctx) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
]==]
[==[
int x509_verify(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	int ret;

	if (!ctx) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
#ifdef ENABLE_SECP384R1
	case OID_ecdsa_with_sha384:
#endif
	case OID_rsasign_with_sha256:
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			x509_key_cleanup(&ctx->key);
			break;
]==]
[==[
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			x509_key_cleanup(&ctx->key);
			break;
#ifdef ENABLE_SECP384R1
		case OID_ecdsa_with_sha384:
			gmssl_secure_clear(&ctx->u, sizeof(ctx->u));
			break;
#endif
]==]
)


# A P-384 public key is retained by X509_KEY; clean it on all paths.
gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
			case OID_secp256r1:
				secp256r1_key_cleanup(&key->u.secp256r1_key);
				break;
#endif
			default:
]==]
[==[
			case OID_secp256r1:
				secp256r1_key_cleanup(&key->u.secp256r1_key);
				break;
#endif
#ifdef ENABLE_SECP384R1
			case OID_secp384r1:
				gmssl_secure_clear(&key->u.secp384r1_key, sizeof(SECP384R1_KEY));
				break;
#endif
			default:
]==]
)

unset(_gmssl_p384_cmake)
unset(_gmssl_p384_h)
unset(_gmssl_p384_c)


# x509_cer.c has a second chain verifier distinct from the x509_vrf.c path
# already adapted by the RSA overlay. Both must respect the certificate's
# actual signed OID, not just the issuer key's default signing preference.
set(_gmssl_p384_cert_c "${SOURCE_PATH}/src/x509_cer.c")
gmssl_replace_once(
    "${_gmssl_p384_cert_c}"
[==[
	int key_sig_alg;
	void *sign_args = NULL;
]==]
[==[
	void *sign_args = NULL;
]==]
)
gmssl_replace_once(
    "${_gmssl_p384_cert_c}"
[==[
	if (x509_key_get_sign_algor(key, &key_sig_alg) != 1) {
		error_print();
		return -1;
	}

	if (x509_signed_from_der(
]==]
[==[
	if (x509_signed_from_der(
]==]
)
gmssl_replace_once(
    "${_gmssl_p384_cert_c}"
[==[
	if (sig_alg != key_sig_alg) {
		error_print();
		return -1;
	}
]==]
[==[
	if (x509_key_supports_sign_algor(key, sig_alg) != 1) {
		error_print();
		return -1;
	}
]==]
)
gmssl_replace_once(
    "${_gmssl_p384_cert_c}"
[==[
	if (x509_verify_init(&verify_ctx, key, sign_args, sign_argslen, sig, siglen) != 1
]==]
[==[
	if (x509_verify_init_ex(&verify_ctx, key, sig_alg, sign_args, sign_argslen, sig, siglen) != 1
]==]
)
unset(_gmssl_p384_cert_c)
