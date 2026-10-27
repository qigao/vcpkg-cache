# GmSSL port source transformations (phase 3/4): RSA TLS and framing.
# Order-preserving consolidation: original source-bearing C/H inputs are now pinned in qigao/crypto.

# --- begin original rsa-pkcs8.cmake (Git blob b0743943cc5975c21dba4e82a729786a9417f21a) ---
# Unencrypted RSA PKCS#8 PrivateKeyInfo loading for Salts TLS identities.
# This layer converts PRIVATE KEY PEM/DER into the bounded RSA_PRIVATE_KEY.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
[==[
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
int rsa_private_key_info_from_der(RSA_PRIVATE_KEY *key,
	const uint8_t **attrs, size_t *attrslen,
	const uint8_t **in, size_t *inlen);
int rsa_private_key_info_from_pem(RSA_PRIVATE_KEY *key, FILE *fp);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
#include <gmssl/sha2.h>
#include <gmssl/asn1.h>
#include <gmssl/error.h>
]==]
[==[
#include <gmssl/sha2.h>
#include <gmssl/asn1.h>
#include <gmssl/pem.h>
#include <gmssl/x509_alg.h>
#include <gmssl/error.h>
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key)
{
	if (key) {
		gmssl_secure_clear(key, sizeof(*key));
	}
}
]==]
[==[
int rsa_private_key_info_from_der(RSA_PRIVATE_KEY *key,
	const uint8_t **attrs, size_t *attrslen,
	const uint8_t **in, size_t *inlen)
{
	const uint8_t *d;
	size_t dlen;
	int version;
	int algor;
	int algor_param;
	const uint8_t *private_key;
	size_t private_key_len;
	const uint8_t *local_attrs = NULL;
	size_t local_attrs_len = 0;
	const uint8_t *p;
	size_t len;

	if (attrs) *attrs = NULL;
	if (attrslen) *attrslen = 0;
	if (!key || !in || !*in || !inlen) {
		error_print();
		return -1;
	}
	if (asn1_sequence_from_der(&d, &dlen, in, inlen) != 1
		|| asn1_int_from_der(&version, &d, &dlen) != 1
		|| x509_public_key_algor_from_der(&algor, &algor_param, &d, &dlen) != 1
		|| asn1_octet_string_from_der(&private_key, &private_key_len, &d, &dlen) != 1
		|| asn1_implicit_set_from_der(0, &local_attrs, &local_attrs_len, &d, &dlen) < 0
		|| asn1_length_is_zero(dlen) != 1) {
		error_print();
		return -1;
	}
	if (version != 0 || algor != OID_rsa_encryption || algor_param != OID_undef
		|| !private_key || !private_key_len) {
		error_print();
		return -1;
	}
	p = private_key;
	len = private_key_len;
	if (rsa_private_key_from_der(key, &p, &len) != 1
		|| asn1_length_is_zero(len) != 1) {
		error_print();
		return -1;
	}
	if (attrs) *attrs = local_attrs;
	if (attrslen) *attrslen = local_attrs_len;
	return 1;
}

int rsa_private_key_info_from_pem(RSA_PRIVATE_KEY *key, FILE *fp)
{
	enum { RSA_PKCS8_MAX_DER_SIZE = 4096 };
	uint8_t buf[RSA_PKCS8_MAX_DER_SIZE];
	const uint8_t *p = buf;
	size_t len = 0;
	const uint8_t *attrs = NULL;
	size_t attrslen = 0;
	int ret = -1;

	if (!key || !fp) {
		error_print();
		return -1;
	}
	if (pem_read(fp, "PRIVATE KEY", buf, &len, sizeof(buf)) != 1
		|| rsa_private_key_info_from_der(key, &attrs, &attrslen, &p, &len) != 1
		|| asn1_length_is_zero(len) != 1
		|| attrslen != 0) {
		error_print();
		goto end;
	}
	ret = 1;

end:
	gmssl_secure_clear(buf, sizeof(buf));
	if (ret != 1) {
		rsa_private_key_cleanup(key);
	}
	return ret;
}

void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key)
{
	if (key) {
		gmssl_secure_clear(key, sizeof(*key));
	}
}
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
# --- end original rsa-pkcs8.cmake ---

# --- begin original rsa-private-signatures.cmake (Git blob f90770642987dbfe1b5b39f2d0b46fe1f40d78cb) ---
# RSA SHA-256 signing encodings built on the bounded CRT private operation.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
]==]
[==[
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
int rsa_sign_pkcs1_v15_sha256(const RSA_PRIVATE_KEY *key,
	const uint8_t dgst[32], uint8_t *sig, size_t sigmax, size_t *siglen);
int rsa_sign_pss_sha256_with_salt(const RSA_PRIVATE_KEY *key,
	const uint8_t dgst[32], const uint8_t salt[32],
	uint8_t *sig, size_t sigmax, size_t *siglen);
int rsa_sign_pss_sha256(const RSA_PRIVATE_KEY *key,
	const uint8_t dgst[32], uint8_t *sig, size_t sigmax, size_t *siglen);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
#include <gmssl/sha2.h>
#include <gmssl/asn1.h>
]==]
[==[
#include <gmssl/sha2.h>
#include <gmssl/rand.h>
#include <gmssl/asn1.h>
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
[==[
int rsa_sign_pkcs1_v15_sha256(const RSA_PRIVATE_KEY *key,
	const uint8_t dgst[32], uint8_t *sig, size_t sigmax, size_t *siglen)
{
	static const uint8_t digest_info_prefix[] = {
		0x30,0x31,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,0x01,
		0x65,0x03,0x04,0x02,0x01,0x05,0x00,0x04,0x20
	};
	uint8_t em[RSA_MAX_MODULUS_SIZE];
	size_t emlen;
	size_t pslen;
	int ret;

	if (siglen) *siglen = 0;
	if (!key || !dgst || !sig || !siglen
		|| key->public_key.modulus_size < RSA_MIN_MODULUS_SIZE
		|| key->public_key.modulus_size > RSA_MAX_MODULUS_SIZE
		|| sigmax < key->public_key.modulus_size) {
		error_print();
		return -1;
	}
	emlen = key->public_key.modulus_size;
	if (emlen < 3 + 8 + sizeof(digest_info_prefix) + SHA256_DIGEST_SIZE) {
		error_print();
		return -1;
	}
	pslen = emlen - 3 - sizeof(digest_info_prefix) - SHA256_DIGEST_SIZE;
	em[0] = 0x00;
	em[1] = 0x01;
	memset(em + 2, 0xff, pslen);
	em[2 + pslen] = 0x00;
	memcpy(em + 3 + pslen, digest_info_prefix, sizeof(digest_info_prefix));
	memcpy(em + 3 + pslen + sizeof(digest_info_prefix), dgst, SHA256_DIGEST_SIZE);

	ret = rsa_private_key_operation(key, em, emlen, sig, sigmax, siglen);
	gmssl_secure_clear(em, sizeof(em));
	return ret;
}

int rsa_sign_pss_sha256_with_salt(const RSA_PRIVATE_KEY *key,
	const uint8_t dgst[32], const uint8_t salt[32],
	uint8_t *sig, size_t sigmax, size_t *siglen)
{
	enum { SALT_LEN = SHA256_DIGEST_SIZE };
	uint8_t em[RSA_MAX_MODULUS_SIZE];
	uint8_t db[RSA_MAX_MODULUS_SIZE];
	uint8_t mask[RSA_MAX_MODULUS_SIZE];
	uint8_t h[SHA256_DIGEST_SIZE];
	uint8_t prefix[8] = {0};
	SHA256_CTX hash_ctx;
	size_t mod_bits;
	size_t em_bits;
	size_t em_len;
	size_t db_len;
	size_t ps_len;
	size_t unused_bits;
	size_t offset;
	size_t i;
	int ret = -1;

	if (siglen) *siglen = 0;
	if (!key || !dgst || !salt || !sig || !siglen
		|| key->public_key.modulus_size < RSA_MIN_MODULUS_SIZE
		|| key->public_key.modulus_size > RSA_MAX_MODULUS_SIZE
		|| sigmax < key->public_key.modulus_size) {
		error_print();
		return -1;
	}
	mod_bits = rsa_modulus_bits(&key->public_key);
	if (mod_bits < 2) {
		error_print();
		return -1;
	}
	em_bits = mod_bits - 1;
	em_len = (em_bits + 7) / 8;
	if (em_len < SHA256_DIGEST_SIZE + SALT_LEN + 2
		|| key->public_key.modulus_size < em_len
		|| key->public_key.modulus_size - em_len > 1) {
		error_print();
		return -1;
	}
	memset(em, 0, sizeof(em));
	memset(db, 0, sizeof(db));
	memset(mask, 0, sizeof(mask));
	memset(h, 0, sizeof(h));
	memset(&hash_ctx, 0, sizeof(hash_ctx));

	sha256_init(&hash_ctx);
	sha256_update(&hash_ctx, prefix, sizeof(prefix));
	sha256_update(&hash_ctx, dgst, SHA256_DIGEST_SIZE);
	sha256_update(&hash_ctx, salt, SALT_LEN);
	sha256_finish(&hash_ctx, h);

	db_len = em_len - SHA256_DIGEST_SIZE - 1;
	ps_len = em_len - SHA256_DIGEST_SIZE - SALT_LEN - 2;
	memset(db, 0, ps_len);
	db[ps_len] = 0x01;
	memcpy(db + ps_len + 1, salt, SALT_LEN);
	if (rsa_mgf1_sha256(h, sizeof(h), mask, db_len) != 1) {
		error_print();
		goto end;
	}
	for (i = 0; i < db_len; i++) {
		db[i] ^= mask[i];
	}
	unused_bits = 8 * em_len - em_bits;
	if (unused_bits) {
		db[0] &= (uint8_t)(0xffu >> unused_bits);
	}

	offset = key->public_key.modulus_size - em_len;
	memcpy(em + offset, db, db_len);
	memcpy(em + offset + db_len, h, sizeof(h));
	em[offset + em_len - 1] = 0xbc;

	ret = rsa_private_key_operation(key, em, key->public_key.modulus_size,
		sig, sigmax, siglen);

end:
	gmssl_secure_clear(em, sizeof(em));
	gmssl_secure_clear(db, sizeof(db));
	gmssl_secure_clear(mask, sizeof(mask));
	gmssl_secure_clear(h, sizeof(h));
	gmssl_secure_clear(&hash_ctx, sizeof(hash_ctx));
	return ret;
}

int rsa_sign_pss_sha256(const RSA_PRIVATE_KEY *key,
	const uint8_t dgst[32], uint8_t *sig, size_t sigmax, size_t *siglen)
{
	uint8_t salt[SHA256_DIGEST_SIZE];
	int ret;

	if (rand_bytes(salt, sizeof(salt)) != 1) {
		error_print();
		return -1;
	}
	ret = rsa_sign_pss_sha256_with_salt(key, dgst, salt, sig, sigmax, siglen);
	gmssl_secure_clear(salt, sizeof(salt));
	return ret;
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
# --- end original rsa-private-signatures.cmake ---

# --- begin original rsa-ext.cmake (Git blob b2c6f7181763af1aae1334a232794e24cc473124) ---
# RFC 8017 encodings over the provider's RSA and digest primitives.
file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/include/gmssl/rsa_ext.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/src/rsa_ext.c"
     DESTINATION "${SOURCE_PATH}/src")
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c" "src/debug.c\nsrc/rsa_ext.c")
# --- end original rsa-ext.cmake ---

# --- begin original x509-rsa.cmake (Git blob 3fd7ceb25fb24a5b31076eac1bced1108709d165) ---
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
int x509_verify_init_ex(X509_SIGN_CTX *ctx, const X509_KEY *key, int sign_algor,
	const void *args, size_t argslen, const uint8_t *sig, size_t siglen)
{
	if (!ctx || !key || !sig || !siglen) {
		error_print();
		return -1;
	}
	switch (key->algor) {
#ifdef ENABLE_SM9
	case OID_sm9:
		if (!args || !argslen) {
			error_print();
			return -1;
		}
		break;
#endif
	case OID_ec_public_key:
		break;
	default:
		if (args) {
			error_print();
			return -1;
		}
	}

	memset(ctx, 0, sizeof(X509_SIGN_CTX));

	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
int x509_verify_init_ex(X509_SIGN_CTX *ctx, const X509_KEY *key, int sign_algor,
	const void *args, size_t argslen, const uint8_t *sig, size_t siglen)
{
	if (!ctx || !key || !sig || !siglen) {
		error_print();
		return -1;
	}
	switch (key->algor) {
#ifdef ENABLE_SM9
	case OID_sm9:
		if (!args || !argslen) {
			error_print();
			return -1;
		}
		break;
#endif
	case OID_ec_public_key:
		break;
	default:
		if (args) {
			error_print();
			return -1;
		}
	}

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
int x509_verify(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	int ret;

	if (!ctx) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
#ifdef ENABLE_SECP256R1
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
	case OID_rsasign_with_sha256:
	case OID_sm2sign_with_sm3:
#ifdef ENABLE_SECP256R1
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
void x509_sign_ctx_cleanup(X509_SIGN_CTX *ctx)
{
	if (ctx) {
		switch (ctx->sign_algor) {
		case OID_sm2sign_with_sm3:
]==]
[==[
void x509_sign_ctx_cleanup(X509_SIGN_CTX *ctx)
{
	if (ctx) {
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
# --- end original x509-rsa.cmake ---

# --- begin original x509-rsa-signing.cmake (Git blob bd1e171ab3b247dfd2af1692ed6a4ebebe25df0c) ---
# RSA private identity ownership and PKCS#1 SHA-256 signing through X509_KEY.
# Keeps RSA public verification storage unchanged and adds a bounded sidecar
# private key only when an identity is loaded.

set(_gmssl_x509_h "${SOURCE_PATH}/include/gmssl/x509_key.h")
set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_x509_h}"
[==[
	} u;
} X509_KEY;
]==]
[==[
	} u;
	RSA_PRIVATE_KEY rsa_private_key;
	int has_private_key;
} X509_KEY;
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
void x509_key_cleanup(X509_KEY *key)
{
	if (key) {
]==]
[==[
void x509_key_cleanup(X509_KEY *key)
{
	if (key) {
		if (key->algor == OID_rsa_encryption && key->has_private_key) {
			rsa_private_key_cleanup(&key->rsa_private_key);
			key->has_private_key = 0;
		}
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
	if (!key || !fp) {
		error_print();
		return -1;
	}

	if (algor == OID_ec_public_key) {
]==]
[==[
int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
	if (!key || !fp) {
		error_print();
		return -1;
	}

	if (algor == OID_rsa_encryption) {
		RSA_PRIVATE_KEY private_key;
		memset(&private_key, 0, sizeof(private_key));
		if (rsa_private_key_info_from_pem(&private_key, fp) != 1) {
			rsa_private_key_cleanup(&private_key);
			error_print();
			return -1;
		}
		memset(key, 0, sizeof(*key));
		key->algor = OID_rsa_encryption;
		key->algor_param = OID_undef;
		key->u.rsa_public_key = private_key.public_key;
		key->rsa_private_key = private_key;
		key->has_private_key = 1;
		gmssl_secure_clear(&private_key, sizeof(private_key));
		return 1;
	}

	if (algor == OID_ec_public_key) {
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

	switch (key->algor) {
	case OID_rsa_encryption:
		if (args || argslen || !key->has_private_key
			|| key->rsa_private_key.public_key.modulus_size != key->u.rsa_public_key.modulus_size
			|| key->rsa_private_key.public_key.public_exponent != key->u.rsa_public_key.public_exponent
			|| gmssl_secure_memcmp(key->rsa_private_key.public_key.modulus,
				key->u.rsa_public_key.modulus,
				key->u.rsa_public_key.modulus_size) != 0) {
			error_print();
			return -1;
		}
		sha256_init(&ctx->u.rsa_verify_ctx);
		ctx->key = *key;
		ctx->sign_algor = OID_rsasign_with_sha256;
		break;
	case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_sign_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	if (!ctx) {
		error_print();
		return -1;
	}

	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
]==]
[==[
int x509_sign_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	if (!ctx) {
		error_print();
		return -1;
	}

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
int x509_sign_finish(X509_SIGN_CTX *ctx, uint8_t *sig, size_t *siglen)
{
	if (!ctx || !sig || !siglen) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
		if (ctx->fixed_siglen) {
]==]
[==[
int x509_sign_finish(X509_SIGN_CTX *ctx, uint8_t *sig, size_t *siglen)
{
	if (!ctx || !sig || !siglen) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256: {
		uint8_t dgst[SHA256_DIGEST_SIZE];
		int ret;
		sha256_finish(&ctx->u.rsa_verify_ctx, dgst);
		ret = rsa_sign_pkcs1_v15_sha256(&ctx->key.rsa_private_key,
			dgst, sig, ctx->key.u.rsa_public_key.modulus_size, siglen);
		gmssl_secure_clear(dgst, sizeof(dgst));
		if (ret != 1) {
			error_print();
			return -1;
		}
		break;
	}
	case OID_sm2sign_with_sm3:
		if (ctx->fixed_siglen) {
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_sign(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen, uint8_t *sig, size_t *siglen)
{
	if (!ctx || !sig || !siglen) {
		error_print();
		return -1;
	}
	if (!data || !datalen) {
		error_print();
		return -1;
	}

	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
#ifdef ENABLE_SECP256R1
]==]
[==[
int x509_sign(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen, uint8_t *sig, size_t *siglen)
{
	if (!ctx || !sig || !siglen) {
		error_print();
		return -1;
	}
	if (!data || !datalen) {
		error_print();
		return -1;
	}

	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
	case OID_sm2sign_with_sm3:
#ifdef ENABLE_SECP256R1
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			break;
]==]
[==[
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			x509_key_cleanup(&ctx->key);
			break;
]==]
)

unset(_gmssl_x509_h)
unset(_gmssl_x509_c)
# --- end original x509-rsa-signing.cmake ---

# --- begin original rsa-encrypted-pkcs8.cmake (Git blob c0fd72e47db8ed1683f8ee674d9434056ba8e6de) ---
# OpenSSL-compatible encrypted RSA PKCS#8 support required by Salts key_password.
# Preserve the existing SM4/HMAC-SM3 generic PKCS#8 behavior while adding the
# bounded PBES2/PBKDF2/HMAC-SHA256/AES-256-CBC decode path used by ordinary
# OpenSSL "ENCRYPTED PRIVATE KEY" identities.

set(_gmssl_pkcs8_c "${SOURCE_PATH}/src/pkcs8.c")
set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_pkcs8_c}"
[==[
static const uint32_t oid_hmac_sm3[] = { oid_sm_algors,401,2 };
static const size_t oid_hmac_sm3_cnt = sizeof(oid_hmac_sm3)/sizeof(oid_hmac_sm3[0]);
]==]
[==[
static const uint32_t oid_hmac_sm3[] = { oid_sm_algors,401,2 };
static const size_t oid_hmac_sm3_cnt = sizeof(oid_hmac_sm3)/sizeof(oid_hmac_sm3[0]);
static const uint32_t oid_hmac_sha256[] = { 1,2,840,113549,2,9 };
static const size_t oid_hmac_sha256_cnt = sizeof(oid_hmac_sha256)/sizeof(oid_hmac_sha256[0]);
]==]
)

gmssl_replace_once(
    "${_gmssl_pkcs8_c}"
[==[
int pbkdf2_prf_from_der(int *oid, const uint8_t **in, size_t *inlen)
{
	int ret;
	const uint8_t *d;
	size_t dlen;
	uint32_t nodes[32];
	size_t nodes_cnt;

	if ((ret = asn1_sequence_from_der(&d, &dlen, in, inlen)) != 1) {
		if (ret < 0) error_print();
		else *oid = -1;
		return ret;
	}
	if (asn1_object_identifier_from_der(nodes, &nodes_cnt, &d, &dlen) != 1
		|| asn1_object_identifier_equ(nodes, nodes_cnt, oid_hmac_sm3, oid_hmac_sm3_cnt) != 1
		|| asn1_length_is_zero(dlen) != 1) {
		error_print();
		return -1;
	}
	*oid = OID_hmac_sm3;
	return 1;
}
]==]
[==[
int pbkdf2_prf_from_der(int *oid, const uint8_t **in, size_t *inlen)
{
	int ret;
	const uint8_t *d;
	size_t dlen;
	uint32_t nodes[32];
	size_t nodes_cnt;

	if ((ret = asn1_sequence_from_der(&d, &dlen, in, inlen)) != 1) {
		if (ret < 0) error_print();
		else *oid = -1;
		return ret;
	}
	if (asn1_object_identifier_from_der(nodes, &nodes_cnt, &d, &dlen) != 1) {
		error_print();
		return -1;
	}
	if (asn1_object_identifier_equ(nodes, nodes_cnt, oid_hmac_sm3, oid_hmac_sm3_cnt) == 1) {
		*oid = OID_hmac_sm3;
	} else if (asn1_object_identifier_equ(nodes, nodes_cnt,
			oid_hmac_sha256, oid_hmac_sha256_cnt) == 1) {
		*oid = OID_hmac_sha256;
	} else {
		error_print();
		return -1;
	}
	/* OpenSSL emits AlgorithmIdentifier parameters as NULL; GmSSL's SM3
	 * writer omits them. Accept both canonical encodings. */
	if (dlen && asn1_null_from_der(&d, &dlen) != 1) {
		error_print();
		return -1;
	}
	if (asn1_length_is_zero(dlen) != 1) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
)

gmssl_replace_once(
    "${_gmssl_pkcs8_c}"
[==[
	if (*oid != OID_sm4_cbc) {
		error_print();
		return -1;
	}
]==]
[==[
	if (*oid != OID_sm4_cbc && *oid != OID_aes256_cbc) {
		error_print();
		return -1;
	}
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
#include <gmssl/sm4.h>
#include <gmssl/rsa.h>
]==]
[==[
#include <gmssl/sm4.h>
#include <gmssl/aes.h>
#include <gmssl/pbkdf2.h>
#include <gmssl/rsa.h>
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
]==]
[==[
static int x509_rsa_private_key_from_encrypted_pem(
	RSA_PRIVATE_KEY *private_key, const char *pass, FILE *fp)
{
	enum { RSA_ENCRYPTED_PKCS8_MAX_DER_SIZE = 8192 };
	uint8_t encoded[RSA_ENCRYPTED_PKCS8_MAX_DER_SIZE];
	uint8_t plaintext[RSA_ENCRYPTED_PKCS8_MAX_DER_SIZE];
	uint8_t raw_key[AES256_KEY_SIZE];
	AES_KEY aes_key;
	const uint8_t *p = encoded;
	size_t encoded_len = 0;
	const uint8_t *salt = NULL;
	size_t saltlen = 0;
	int iter = 0;
	int keylen = 0;
	int prf = OID_undef;
	int cipher = OID_undef;
	const uint8_t *iv = NULL;
	size_t ivlen = 0;
	const uint8_t *encrypted = NULL;
	size_t encrypted_len = 0;
	size_t plaintext_len = 0;
	const uint8_t *attrs = NULL;
	size_t attrslen = 0;
	int ret = -1;

	memset(encoded, 0, sizeof(encoded));
	memset(plaintext, 0, sizeof(plaintext));
	memset(raw_key, 0, sizeof(raw_key));
	memset(&aes_key, 0, sizeof(aes_key));
	memset(private_key, 0, sizeof(*private_key));

	if (!pass || !pass[0] || !fp) {
		error_print();
		goto end;
	}
	if (pem_read(fp, "ENCRYPTED PRIVATE KEY",
			encoded, &encoded_len, sizeof(encoded)) != 1) {
		error_print();
		goto end;
	}
	if (pkcs8_enced_private_key_info_from_der(
			&salt, &saltlen, &iter, &keylen, &prf,
			&cipher, &iv, &ivlen, &encrypted, &encrypted_len,
			&p, &encoded_len) != 1
		|| asn1_length_is_zero(encoded_len) != 1
		|| !salt || saltlen == 0 || saltlen > PBKDF2_MAX_SALT_SIZE
		|| iter <= 0
		|| (keylen != -1 && keylen != AES256_KEY_SIZE)
		|| prf != OID_hmac_sha256
		|| cipher != OID_aes256_cbc
		|| !iv || ivlen != AES_BLOCK_SIZE
		|| !encrypted || encrypted_len == 0
		|| encrypted_len > sizeof(plaintext)) {
		error_print();
		goto end;
	}
	if (pbkdf2_hmac_genkey(DIGEST_sha256(),
			pass, strlen(pass), salt, saltlen, (size_t)iter,
			sizeof(raw_key), raw_key) != 1
		|| aes_set_decrypt_key(&aes_key, raw_key, sizeof(raw_key)) != 1
		|| aes_cbc_padding_decrypt(&aes_key, iv,
			encrypted, encrypted_len, plaintext, &plaintext_len) != 1) {
		error_print();
		goto end;
	}
	p = plaintext;
	if (rsa_private_key_info_from_der(private_key,
			&attrs, &attrslen, &p, &plaintext_len) != 1
		|| asn1_length_is_zero(plaintext_len) != 1
		|| attrslen != 0) {
		error_print();
		goto end;
	}
	ret = 1;

end:
	gmssl_secure_clear(&aes_key, sizeof(aes_key));
	gmssl_secure_clear(raw_key, sizeof(raw_key));
	gmssl_secure_clear(plaintext, sizeof(plaintext));
	gmssl_secure_clear(encoded, sizeof(encoded));
	return ret;
}

int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (algor == OID_rsa_encryption) {
		RSA_PRIVATE_KEY private_key;
		memset(&private_key, 0, sizeof(private_key));
		if (rsa_private_key_info_from_pem(&private_key, fp) != 1) {
			rsa_private_key_cleanup(&private_key);
			error_print();
			return -1;
		}
]==]
[==[
	if (algor == OID_rsa_encryption) {
		RSA_PRIVATE_KEY private_key;
		int load_ret;
		memset(&private_key, 0, sizeof(private_key));
		load_ret = pass && pass[0]
			? x509_rsa_private_key_from_encrypted_pem(&private_key, pass, fp)
			: rsa_private_key_info_from_pem(&private_key, fp);
		if (load_ret != 1) {
			rsa_private_key_cleanup(&private_key);
			error_print();
			return -1;
		}
]==]
)

unset(_gmssl_pkcs8_c)
unset(_gmssl_x509_c)
# --- end original rsa-encrypted-pkcs8.cmake ---

# --- begin original tls13-rsa.cmake (Git blob 10c2f056b8833ee18de229ef5fb8abfb494f93fa) ---
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
	/* TLS 1.3 CertificateVerify must prefer RSA-PSS. Keep PKCS#1 after it
	 * so ordinary sha256WithRSAEncryption certificate chains remain selectable
	 * when signature_algorithms_cert is not sent separately. */
	TLS_sig_rsa_pss_rsae_sha256,
	TLS_sig_rsa_pkcs1_sha256,
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


# TLS 1.3 cipher suites are independent of the authentication key family but
# still select a transcript digest. RSA-PSS/SHA-256 must therefore map
# directly to SHA-256 here; do not fake an X.509 AlgorithmIdentifier mapping.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	switch (tls_signature_scheme_algorithm_oid(sig_alg)) {
	case OID_sm2sign_with_sm3:
		digest_oid = OID_sm3;
		break;
	case OID_ecdsa_with_sha256:
		digest_oid = OID_sha256;
		break;
	default:
		error_print();
		return -1;
	}
]==]
[==[
	if (sig_alg == TLS_sig_rsa_pss_rsae_sha256) {
		digest_oid = OID_sha256;
	} else {
		switch (tls_signature_scheme_algorithm_oid(sig_alg)) {
		case OID_sm2sign_with_sm3:
			digest_oid = OID_sm3;
			break;
		case OID_ecdsa_with_sha256:
			digest_oid = OID_sha256;
			break;
		default:
			error_print();
			return -1;
		}
	}
]==]
)

unset(_gmssl_tls13_c)
unset(_gmssl_tls_trace_c)
# --- end original tls13-rsa.cmake ---

# --- begin original tls12-rsa.cmake (Git blob acc50fdface74aa7b09aba89a5c8564fc0858247) ---
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


# tls12_send() dispatches application data directly instead of using
# tls_record_encrypt(), so add ECDHE_RSA to its AES-GCM path explicitly.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		case TLS_cipher_ecdhe_sm4_gcm_sm3:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
			if (tls_gcm_encrypt(enc_key, fixed_iv, seq_num, conn->databuf,
]==]
[==[
		case TLS_cipher_ecdhe_sm4_gcm_sm3:
		case TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256:
		case TLS_cipher_ecdhe_rsa_with_aes_128_gcm_sha256:
			if (tls_gcm_encrypt(enc_key, fixed_iv, seq_num, conn->databuf,
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
unset(_gmssl_tls12_c)
unset(_gmssl_tls_vrf_c)
unset(_gmssl_tls_trace_c)
# --- end original tls12-rsa.cmake ---

# --- begin original tls12-rsa-server-signing.cmake (Git blob 05b83cf9b72de18c2b7fcc1887bb233f37f66f71) ---
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
# --- end original tls12-rsa-server-signing.cmake ---

# --- begin original tls12-rsa-mtls.cmake (Git blob 8071d1e81a78735f6aa9db138ca86b1f13dd5b61) ---
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
# --- end original tls12-rsa-mtls.cmake ---

# --- begin original tls13-rsa-signing.cmake (Git blob 8809cd345065a67cd991a35ad1aeeb93b023da28) ---
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
# --- end original tls13-rsa-signing.cmake ---

# --- begin original handshake-framing.cmake (Git blob a8789f57ccba93ede57348308db7443151bc631f) ---
# Encrypted TLS 1.3 handshake messages are independent of record boundaries.
set(_gmssl_tls13 "${SOURCE_PATH}/src/tls13.c")
file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/src/tls13-handshake-reader.h" DESTINATION "${SOURCE_PATH}/src")

gmssl_replace_once("${SOURCE_PATH}/include/gmssl/tls.h"
[==[
	uint8_t plain_record[TLS_MAX_RECORD_SIZE];]==]
[==[
	/* Owned by the handshake progress caller; bounded across nonblocking retries. */
	uint8_t handshake_fragment[TLS_MAX_RECORD_SIZE];
	size_t handshake_fragment_len;
	size_t handshake_fragment_offset;
	size_t handshake_message_len;
	int handshake_message_pending;
	uint8_t plain_record[TLS_MAX_RECORD_SIZE];]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_encrypted_extensions(TLS_CONNECT *conn)]==]
[==[

#include "tls13-handshake-reader.h"

int tls13_recv_encrypted_extensions(TLS_CONNECT *conn)]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_encrypted_extensions(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *exts;
	size_t extslen;

	const uint8_t *supported_groups = NULL;

	int server_name = 0;
	int early_data = 0;
	int alpn = 0;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv {EncryptedExtensions}\n");
	if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
		conn->server_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->server_seq_num);]==]
[==[
int tls13_recv_encrypted_extensions(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *exts;
	size_t extslen;

	const uint8_t *supported_groups = NULL;

	int server_name = 0;
	int early_data = 0;
	int alpn = 0;

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_certificate_request(TLS_CONNECT *conn)
{
	int ret;
	int handshake_type;
	const uint8_t *handshake_data;
	size_t handshake_datalen;
	int client_cert = 0;

	// certificate_request
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *exts;
	size_t extslen;

	// extensions
	const uint8_t *signature_algorithms = NULL;
	size_t signature_algorithms_len;
	const uint8_t *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_len;
	const uint8_t *certificate_authorities = NULL;
	size_t certificate_authorities_len;
	const uint8_t *oid_filters = NULL;
	size_t oid_filters_len;
	int status_request = 0;
	int signed_certificate_timestamp = 0;

	int common_sig_algs[4];
	size_t common_sig_algs_cnt;
	int common_sig_algs_cert[4];
	size_t common_sig_algs_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *filters = NULL;
	size_t filters_len = 0;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv {CertificateRequest*}\n");

	if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
		conn->server_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->server_seq_num);]==]
[==[
int tls13_recv_certificate_request(TLS_CONNECT *conn)
{
	int ret;
	int handshake_type;
	const uint8_t *handshake_data;
	size_t handshake_datalen;
	int client_cert = 0;

	// certificate_request
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *exts;
	size_t extslen;

	// extensions
	const uint8_t *signature_algorithms = NULL;
	size_t signature_algorithms_len;
	const uint8_t *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_len;
	const uint8_t *certificate_authorities = NULL;
	size_t certificate_authorities_len;
	const uint8_t *oid_filters = NULL;
	size_t oid_filters_len;
	int status_request = 0;
	int signed_certificate_timestamp = 0;

	int common_sig_algs[4];
	size_t common_sig_algs_cnt;
	int common_sig_algs_cert[4];
	size_t common_sig_algs_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *filters = NULL;
	size_t filters_len = 0;

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_server_certificate(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *leaf_status_request_ocsp_response = NULL;
	size_t leaf_status_request_ocsp_response_len = 0;
	const uint8_t *leaf_signed_certificate_timestamp;
	size_t leaf_signed_certificate_timestamp_len;
	const uint8_t *cert;
	size_t certlen;

	const int *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *host_name = NULL;
	size_t host_name_len = 0;

	int verify_result = X509_verify_ok;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv server {Certificate}\n");

	// decrypt unless previous handshake is CertificateRequest
	if (!conn->plain_recordlen) {
		if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
			conn->server_seq_num, conn->record, conn->recordlen,
			conn->plain_record, &conn->plain_recordlen) != 1) {
			error_print();
			tls13_send_alert(conn, TLS_alert_bad_record_mac);
			return -1;
		}
		tls_seq_num_incr(conn->server_seq_num);

	}]==]
[==[
int tls13_recv_server_certificate(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *leaf_status_request_ocsp_response = NULL;
	size_t leaf_status_request_ocsp_response_len = 0;
	const uint8_t *leaf_signed_certificate_timestamp;
	size_t leaf_signed_certificate_timestamp_len;
	const uint8_t *cert;
	size_t certlen;

	const int *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *host_name = NULL;
	size_t host_name_len = 0;

	int verify_result = X509_verify_ok;

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_server_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	int sig_alg;
	const uint8_t *sig;
	size_t siglen;
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv server {CertificateVerify}\n");

	if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
		conn->server_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->server_seq_num);]==]
[==[
int tls13_recv_server_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	int sig_alg;
	const uint8_t *sig;
	size_t siglen;
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_client_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	int sig_alg;
	const uint8_t *sig;
	size_t siglen;
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv client {CertificateVerify}\n");

	if (tls13_record_decrypt(conn->cipher_suite, &conn->client_write_key, conn->client_write_iv,
		conn->client_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->client_seq_num);]==]
[==[
int tls13_recv_client_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	int sig_alg;
	const uint8_t *sig;
	size_t siglen;
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if ((ret = tls13_recv_handshake_message(conn, 0)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_server_finished(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *server_verify_data;
	size_t server_verify_data_len;
	uint8_t verify_data[64];
	size_t verify_data_len;

	// compute verify_data before digest_update
	if (tls13_compute_verify_data(conn->server_handshake_traffic_secret,
		&conn->dgst_ctx, verify_data, &verify_data_len) != 1) {
		error_print();
		return -1;
	}

	if (!conn->plain_recordlen) {

		if ((ret = tls_recv_record(conn)) != 1) {
			if (ret != TLS_ERROR_RECV_AGAIN) {
				error_print();
			}
			return ret;
		}

		if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
			conn->server_seq_num, conn->record, conn->recordlen,
			conn->plain_record, &conn->plain_recordlen) != 1) {
			error_print();
			tls13_send_alert(conn, TLS_alert_bad_record_mac);
			return -1;
		}
		tls_seq_num_incr(conn->server_seq_num);
	}]==]
[==[
int tls13_recv_server_finished(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *server_verify_data;
	size_t server_verify_data_len;
	uint8_t verify_data[64];
	size_t verify_data_len;

	// compute verify_data before digest_update
	if (tls13_compute_verify_data(conn->server_handshake_traffic_secret,
		&conn->dgst_ctx, verify_data, &verify_data_len) != 1) {
		error_print();
		return -1;
	}

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_client_certificate(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *status_request_ocsp_response = NULL;
	size_t status_request_ocsp_response_len = 0;
	const uint8_t *signed_certificate_timestamp = NULL;
	size_t signed_certificate_timestamp_len;
	const uint8_t *cert;
	size_t certlen;

	const int *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *oid_filters = NULL;
	size_t oid_filters_len = 0;

	int verify_result = X509_verify_ok;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv client {Certificate*}\n");

	if (tls_record_protocol(conn->record) != TLS_protocol_tls12) {
		error_print();
		tls13_send_alert(conn, TLS_alert_protocol_version);
		return -1;
	}

	//format_print(stderr, 0, 0, "client_seq_num: "PRIu64"\n", GETU64(conn->client_seq_num));

	if (tls13_record_decrypt(conn->cipher_suite, &conn->client_write_key, conn->client_write_iv,
		conn->client_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->client_seq_num);]==]
[==[
int tls13_recv_client_certificate(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *status_request_ocsp_response = NULL;
	size_t status_request_ocsp_response_len = 0;
	const uint8_t *signed_certificate_timestamp = NULL;
	size_t signed_certificate_timestamp_len;
	const uint8_t *cert;
	size_t certlen;

	const int *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *oid_filters = NULL;
	size_t oid_filters_len = 0;

	int verify_result = X509_verify_ok;

	if ((ret = tls13_recv_handshake_message(conn, 0)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_client_finished(TLS_CONNECT *conn)
{
	int ret;

	// Finished
	uint8_t local_verify_data[64];
	size_t local_verify_data_len;
	const uint8_t *verify_data;
	size_t verify_data_len;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv client {Finished}\n");

	if (tls_record_protocol(conn->record) != TLS_protocol_tls12) {
		error_print();
		tls13_send_alert(conn, TLS_alert_protocol_version);
		return -1;
	}

	//format_print(stderr, 0, 0, "client_seq_num: "PRIu64"\n", GETU64(conn->client_seq_num));

	if (tls13_record_decrypt(conn->cipher_suite, &conn->client_write_key, conn->client_write_iv,
		conn->client_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->client_seq_num);]==]
[==[
int tls13_recv_client_finished(TLS_CONNECT *conn)
{
	int ret;

	// Finished
	uint8_t local_verify_data[64];
	size_t local_verify_data_len;
	const uint8_t *verify_data;
	size_t verify_data_len;

	if ((ret = tls13_recv_handshake_message(conn, 0)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
	if (handshake_type != TLS_handshake_certificate_request) {]==]
[==[
	if (handshake_type != TLS_handshake_certificate_request) {
		conn->handshake_message_pending = 1;]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
static int tls13_recv_change_cipher_spec_if_present(TLS_CONNECT *conn)
{
	int ret;]==]
[==[
static int tls13_recv_change_cipher_spec_if_present(TLS_CONNECT *conn)
{
	int ret;

	/* A coalesced next handshake already rules out an intervening CCS. */
	if (conn->handshake_fragment_offset < conn->handshake_fragment_len) return 0;]==])

unset(_gmssl_tls13)
# --- end original handshake-framing.cmake ---

