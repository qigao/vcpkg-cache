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
