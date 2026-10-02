# X.509 RSA public-key storage and SHA-256 certificate verification.
# Verification-only: RSA private/signing support is intentionally out of scope.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")
set(_gmssl_x509_h "${SOURCE_PATH}/include/gmssl/x509_key.h")
set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")
set(_gmssl_x509_vrf_c "${SOURCE_PATH}/src/x509_vrf.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);
]==]
[==[
int rsa_public_key_to_der(const RSA_PUBLIC_KEY *key, uint8_t **out, size_t *outlen);
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen)
{
]==]
[==[
int rsa_public_key_to_der(const RSA_PUBLIC_KEY *key, uint8_t **out, size_t *outlen)
{
	size_t len = 0;

	if (!key || !outlen
		|| key->modulus_size < RSA_MIN_MODULUS_SIZE
		|| key->modulus_size > RSA_MAX_MODULUS_SIZE
		|| (key->modulus_size & 3u) != 0
		|| key->modulus[0] == 0
		|| (key->modulus[key->modulus_size - 1] & 1u) == 0
		|| key->public_exponent < 3
		|| key->public_exponent > 0x7fffffffu
		|| (key->public_exponent & 1u) == 0) {
		error_print();
		return -1;
	}
	if (asn1_integer_to_der(key->modulus, key->modulus_size, NULL, &len) != 1
		|| asn1_int_to_der((int)key->public_exponent, NULL, &len) != 1
		|| asn1_sequence_header_to_der(len, out, outlen) != 1
		|| asn1_integer_to_der(key->modulus, key->modulus_size, out, outlen) != 1
		|| asn1_int_to_der((int)key->public_exponent, out, outlen) != 1) {
		error_print();
		return -1;
	}
	return 1;
}

int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_h}"
[==[
#include <gmssl/digest.h>
#include <gmssl/sm2.h>
]==]
[==[
#include <gmssl/digest.h>
#include <gmssl/rsa.h>
#include <gmssl/sm2.h>
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_h}"
[==[
	union {
		SM2_KEY sm2_key;
]==]
[==[
	union {
		RSA_PUBLIC_KEY rsa_public_key;
		SM2_KEY sm2_key;
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_h}"
[==[
int x509_key_set_sm2_key(X509_KEY *x509_key, const SM2_KEY *sm2_key);
]==]
[==[
int x509_key_set_rsa_public_key(X509_KEY *x509_key, const RSA_PUBLIC_KEY *rsa_public_key);
int x509_key_set_sm2_key(X509_KEY *x509_key, const SM2_KEY *sm2_key);
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_h}"
[==[
	union {
		SM2_SIGN_CTX sm2_sign_ctx;
]==]
[==[
	union {
		SHA256_CTX rsa_verify_ctx;
		SM2_SIGN_CTX sm2_sign_ctx;
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_h}"
[==[
int x509_key_get_sign_algor(const X509_KEY *key, int *algor);
]==]
[==[
int x509_key_supports_sign_algor(const X509_KEY *key, int algor);
int x509_key_get_sign_algor(const X509_KEY *key, int *algor);
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_h}"
[==[
int x509_verify_init(X509_SIGN_CTX *ctx, const X509_KEY *key, const void *args, size_t argslen,
	const uint8_t *sig, size_t siglen);
]==]
[==[
int x509_verify_init_ex(X509_SIGN_CTX *ctx, const X509_KEY *key, int sign_algor,
	const void *args, size_t argslen, const uint8_t *sig, size_t siglen);
int x509_verify_init(X509_SIGN_CTX *ctx, const X509_KEY *key, const void *args, size_t argslen,
	const uint8_t *sig, size_t siglen);
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_key_set_sm2_key(X509_KEY *x509_key, const SM2_KEY *sm2_key)
{
]==]
[==[
int x509_key_set_rsa_public_key(X509_KEY *x509_key, const RSA_PUBLIC_KEY *rsa_public_key)
{
	if (!x509_key || !rsa_public_key) {
		error_print();
		return -1;
	}
	memset(x509_key, 0, sizeof(*x509_key));
	x509_key->algor = OID_rsa_encryption;
	x509_key->algor_param = OID_undef;
	x509_key->u.rsa_public_key = *rsa_public_key;
	return 1;
}

int x509_key_set_sm2_key(X509_KEY *x509_key, const SM2_KEY *sm2_key)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
void x509_key_cleanup(X509_KEY *key)
{
	if (key) {
		if (!key->algor) {
			return;
		}
		switch (key->algor) {
		case OID_ec_public_key:
]==]
[==[
void x509_key_cleanup(X509_KEY *key)
{
	if (key) {
		if (!key->algor) {
			return;
		}
		switch (key->algor) {
		case OID_rsa_encryption:
			gmssl_secure_clear(&key->u.rsa_public_key, sizeof(RSA_PUBLIC_KEY));
			break;
		case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_public_key_to_bytes(const X509_KEY *key, uint8_t **out, size_t *outlen)
{
	if (!key || !outlen) {
		error_print();
		return -1;
	}

	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
int x509_public_key_to_bytes(const X509_KEY *key, uint8_t **out, size_t *outlen)
{
	if (!key || !outlen) {
		error_print();
		return -1;
	}

	switch (key->algor) {
	case OID_rsa_encryption:
		if (rsa_public_key_to_der(&key->u.rsa_public_key, out, outlen) != 1) {
			error_print();
			return -1;
		}
		break;
	case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_public_key_from_bytes(X509_KEY *key, int algor, int algor_param, const uint8_t **in, size_t *inlen)
{
	if (!key || !in || !(*in) || !inlen) {
		error_print();
		return -1;
	}

	memset(key, 0, sizeof(X509_KEY));
	key->algor = algor;
	key->algor_param = algor_param;

	switch (algor) {
	case OID_ec_public_key:
]==]
[==[
int x509_public_key_from_bytes(X509_KEY *key, int algor, int algor_param, const uint8_t **in, size_t *inlen)
{
	if (!key || !in || !(*in) || !inlen) {
		error_print();
		return -1;
	}

	memset(key, 0, sizeof(X509_KEY));
	key->algor = algor;
	key->algor_param = algor_param;

	switch (algor) {
	case OID_rsa_encryption:
		if (algor_param != OID_undef
			|| rsa_public_key_from_der(&key->u.rsa_public_key, in, inlen) != 1) {
			error_print();
			return -1;
		}
		return 1;
	case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (key->algor_param != pub->algor_param) {
		error_print();
		return 0;
	}
	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
	if (key->algor_param != pub->algor_param) {
		error_print();
		return 0;
	}
	switch (key->algor) {
	case OID_rsa_encryption:
		if (key->u.rsa_public_key.modulus_size != pub->u.rsa_public_key.modulus_size
			|| key->u.rsa_public_key.public_exponent != pub->u.rsa_public_key.public_exponent
			|| gmssl_secure_memcmp(key->u.rsa_public_key.modulus,
				pub->u.rsa_public_key.modulus,
				key->u.rsa_public_key.modulus_size) != 0) {
			return 0;
		}
		return 1;
	case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_public_key_print(FILE *fp, int fmt, int ind, const char *label, const X509_KEY *key)
{
	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
int x509_public_key_print(FILE *fp, int fmt, int ind, const char *label, const X509_KEY *key)
{
	switch (key->algor) {
	case OID_rsa_encryption: {
		uint8_t der[RSA_MAX_MODULUS_SIZE + 32];
		uint8_t *p = der;
		size_t derlen = 0;
		if (rsa_public_key_to_der(&key->u.rsa_public_key, &p, &derlen) != 1
			|| rsa_public_key_print(fp, fmt, ind, label, der, derlen) != 1) {
			error_print();
			return -1;
		}
		break;
	}
	case OID_ec_public_key:
]==]
)

# Existing PEM stack buffers were too small for RSA-4096 SPKI.
gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_public_key_info_to_pem(const X509_KEY *a, FILE *fp)
{
	uint8_t buf[512];
]==]
[==[
int x509_public_key_info_to_pem(const X509_KEY *a, FILE *fp)
{
	uint8_t buf[X509_PUBLIC_KEY_INFO_MAX_SIZE];
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_public_key_info_from_pem(X509_KEY *a, FILE *fp)
{
	uint8_t buf[512];
]==]
[==[
int x509_public_key_info_from_pem(X509_KEY *a, FILE *fp)
{
	uint8_t buf[X509_PUBLIC_KEY_INFO_MAX_SIZE];
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_key_get_sign_algor(const X509_KEY *key, int *algor)
{
]==]
[==[
int x509_key_supports_sign_algor(const X509_KEY *key, int algor)
{
	int default_algor;

	if (!key) {
		error_print();
		return -1;
	}
	if (key->algor == OID_rsa_encryption) {
		return algor == OID_rsasign_with_sha256 ? 1 : 0;
	}
	if (x509_key_get_sign_algor(key, &default_algor) != 1) {
		return -1;
	}
	return algor == default_algor ? 1 : 0;
}

int x509_key_get_sign_algor(const X509_KEY *key, int *algor)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_key_get_sign_algor(const X509_KEY *key, int *algor)
{
	if (!key || !algor) {
		error_print();
		return -1;
	}

	switch (key->algor) {
	case OID_ec_public_key:
		switch (key->algor_param) {
]==]
[==[
int x509_key_get_sign_algor(const X509_KEY *key, int *algor)
{
	if (!key || !algor) {
		error_print();
		return -1;
	}

	switch (key->algor) {
	case OID_rsa_encryption:
		*algor = OID_rsasign_with_sha256;
		break;
	case OID_ec_public_key:
		switch (key->algor_param) {
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_key_get_signature_size(const X509_KEY *key, size_t *siglen)
{
	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
int x509_key_get_signature_size(const X509_KEY *key, size_t *siglen)
{
	switch (key->algor) {
	case OID_rsa_encryption:
		*siglen = key->u.rsa_public_key.modulus_size;
		break;
	case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_verify_init(X509_SIGN_CTX *ctx, const X509_KEY *key, const void *args, size_t argslen,
	const uint8_t *sig, size_t siglen)
{
]==]
[==[
int x509_verify_init_ex(X509_SIGN_CTX *ctx, const X509_KEY *key, int sign_algor,
	const void *args, size_t argslen, const uint8_t *sig, size_t siglen)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	memset(ctx, 0, sizeof(X509_SIGN_CTX));

	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
	memset(ctx, 0, sizeof(X509_SIGN_CTX));

	if (x509_key_supports_sign_algor(key, sign_algor) != 1) {
		return -1;
	}

	switch (key->algor) {
	case OID_rsa_encryption:
		if (args || argslen || sign_algor != OID_rsasign_with_sha256
			|| siglen != key->u.rsa_public_key.modulus_size) {
			error_print();
			return -1;
		}
		sha256_init(&ctx->u.rsa_verify_ctx);
		ctx->key = *key;
		ctx->sign_algor = sign_algor;
		ctx->sig = sig;
		ctx->siglen = siglen;
		break;
	case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	return 1;
}

int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
]==]
[==[
	return 1;
}

int x509_verify_init(X509_SIGN_CTX *ctx, const X509_KEY *key, const void *args, size_t argslen,
	const uint8_t *sig, size_t siglen)
{
	int sign_algor;
	if (x509_key_get_sign_algor(key, &sign_algor) != 1) {
		return -1;
	}
	return x509_verify_init_ex(ctx, key, sign_algor, args, argslen, sig, siglen);
}

int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
]==]
[==[
int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
		sha256_update(&ctx->u.rsa_verify_ctx, data, datalen);
		break;
	case OID_sm2sign_with_sm3:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
		if ((ret = sm2_verify_finish(&ctx->u.sm2_verify_ctx, ctx->sig, ctx->siglen)) < 0) {
]==]
[==[
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256: {
		uint8_t dgst[SHA256_DIGEST_SIZE];
		sha256_finish(&ctx->u.rsa_verify_ctx, dgst);
		ret = rsa_verify_pkcs1_v15_sha256(&ctx->key.u.rsa_public_key,
			dgst, ctx->sig, ctx->siglen);
		gmssl_secure_clear(dgst, sizeof(dgst));
		if (ret < 0) {
			error_print();
			return -1;
		}
		break;
	}
	case OID_sm2sign_with_sm3:
		if ((ret = sm2_verify_finish(&ctx->u.sm2_verify_ctx, ctx->sig, ctx->siglen)) < 0) {
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
#ifdef ENABLE_SECP256R1
]==]
[==[
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
	case OID_sm2sign_with_sm3:
#ifdef ENABLE_SECP256R1
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
		switch (ctx->sign_algor) {
		case OID_sm2sign_with_sm3:
]==]
[==[
		switch (ctx->sign_algor) {
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			break;
		case OID_sm2sign_with_sm3:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_vrf_c}"
[==[
	int key_sig_alg;
	void *sign_args = NULL;
]==]
[==[
	void *sign_args = NULL;
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_vrf_c}"
[==[
	// FIXME: 改为 x509_key_support_algor
	if (x509_key_get_sign_algor(key, &key_sig_alg) != 1) {
		error_print();
		return -1;
	}
	if (sig_alg != key_sig_alg) {
		return 0;
	}
]==]
[==[
	if (x509_key_supports_sign_algor(key, sig_alg) != 1) {
		return 0;
	}
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_vrf_c}"
[==[
	if (x509_verify_init(&verify_ctx, key, sign_args, sign_argslen, sig, siglen) != 1
]==]
[==[
	if (x509_verify_init_ex(&verify_ctx, key, sig_alg, sign_args, sign_argslen, sig, siglen) != 1
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
unset(_gmssl_x509_h)
unset(_gmssl_x509_c)
unset(_gmssl_x509_vrf_c)
