# RSA signature encoding verification built on the bounded raw public operation.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

vcpkg_replace_string(
    "${_gmssl_rsa_h}"
    "int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);"
    "int rsa_verify_pkcs1_v15_sha256(const RSA_PUBLIC_KEY *key,\n\tconst uint8_t dgst[32], const uint8_t *sig, size_t siglen);\nint rsa_verify_pss_sha256(const RSA_PUBLIC_KEY *key,\n\tconst uint8_t dgst[32], const uint8_t *sig, size_t siglen);\nint rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "#include <gmssl/mem.h>\n#include <gmssl/asn1.h>"
    "#include <gmssl/mem.h>\n#include <gmssl/sha2.h>\n#include <gmssl/asn1.h>"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)\n{"
    [==[
static int rsa_mgf1_sha256(const uint8_t *seed, size_t seedlen, uint8_t *out, size_t outlen)
{
	uint32_t counter = 0;

	if ((!seed && seedlen) || (!out && outlen)) {
		error_print();
		return -1;
	}
	while (outlen) {
		SHA256_CTX ctx;
		uint8_t block[SHA256_DIGEST_SIZE];
		uint8_t count[4];
		size_t n = outlen < sizeof(block) ? outlen : sizeof(block);

		count[0] = (uint8_t)(counter >> 24);
		count[1] = (uint8_t)(counter >> 16);
		count[2] = (uint8_t)(counter >> 8);
		count[3] = (uint8_t)counter;
		sha256_init(&ctx);
		sha256_update(&ctx, seed, seedlen);
		sha256_update(&ctx, count, sizeof(count));
		sha256_finish(&ctx, block);
		memcpy(out, block, n);
		out += n;
		outlen -= n;
		counter++;
		gmssl_secure_clear(&ctx, sizeof(ctx));
		gmssl_secure_clear(block, sizeof(block));
	}
	return 1;
}

static size_t rsa_modulus_bits(const RSA_PUBLIC_KEY *key)
{
	uint8_t b;
	size_t bits;

	if (!key || !key->modulus_size || key->modulus[0] == 0) return 0;
	b = key->modulus[0];
	bits = (key->modulus_size - 1) * 8;
	while (b) {
		bits++;
		b >>= 1;
	}
	return bits;
}

int rsa_verify_pkcs1_v15_sha256(const RSA_PUBLIC_KEY *key,
	const uint8_t dgst[32], const uint8_t *sig, size_t siglen)
{
	static const uint8_t digest_info_prefix[] = {
		0x30,0x31,0x30,0x0d,0x06,0x09,0x60,0x86,0x48,0x01,
		0x65,0x03,0x04,0x02,0x01,0x05,0x00,0x04,0x20
	};
	uint8_t em[RSA_MAX_MODULUS_SIZE];
	size_t emlen = 0;
	size_t i;
	int ret = 0;

	if (!key || !dgst || !sig || siglen != key->modulus_size) {
		error_print();
		return -1;
	}
	if (rsa_public_key_operation(key, sig, siglen, em, sizeof(em), &emlen) != 1) {
		return 0;
	}
	if (emlen < 3 + 8 + sizeof(digest_info_prefix) + SHA256_DIGEST_SIZE
		|| em[0] != 0x00 || em[1] != 0x01) {
		goto end;
	}
	i = 2;
	while (i < emlen && em[i] == 0xff) i++;
	if (i < 10 || i >= emlen || em[i] != 0x00) goto end;
	i++;
	if (emlen - i != sizeof(digest_info_prefix) + SHA256_DIGEST_SIZE) goto end;
	if (gmssl_secure_memcmp(em + i, digest_info_prefix, sizeof(digest_info_prefix)) != 0) goto end;
	i += sizeof(digest_info_prefix);
	if (gmssl_secure_memcmp(em + i, dgst, SHA256_DIGEST_SIZE) != 0) goto end;
	ret = 1;

end:
	gmssl_secure_clear(em, sizeof(em));
	return ret;
}

int rsa_verify_pss_sha256(const RSA_PUBLIC_KEY *key,
	const uint8_t dgst[32], const uint8_t *sig, size_t siglen)
{
	enum { SALT_LEN = SHA256_DIGEST_SIZE };
	uint8_t recovered[RSA_MAX_MODULUS_SIZE];
	uint8_t db[RSA_MAX_MODULUS_SIZE];
	uint8_t mask[RSA_MAX_MODULUS_SIZE];
	uint8_t expected_h[SHA256_DIGEST_SIZE];
	uint8_t prefix[8] = {0};
	SHA256_CTX hash_ctx;
	size_t recovered_len = 0;
	size_t mod_bits;
	size_t em_bits;
	size_t em_len;
	size_t offset;
	size_t db_len;
	size_t ps_len;
	size_t unused_bits;
	const uint8_t *em;
	const uint8_t *h;
	const uint8_t *salt;
	size_t i;
	int ret = 0;

	if (!key || !dgst || !sig || siglen != key->modulus_size) {
		error_print();
		return -1;
	}
	mod_bits = rsa_modulus_bits(key);
	if (mod_bits < 2) return -1;
	em_bits = mod_bits - 1;
	em_len = (em_bits + 7) / 8;
	if (em_len < SHA256_DIGEST_SIZE + SALT_LEN + 2
		|| key->modulus_size < em_len
		|| key->modulus_size - em_len > 1) {
		error_print();
		return -1;
	}
	if (rsa_public_key_operation(key, sig, siglen,
			recovered, sizeof(recovered), &recovered_len) != 1) {
		return 0;
	}
	if (recovered_len != key->modulus_size) goto end;
	offset = recovered_len - em_len;
	for (i = 0; i < offset; i++) {
		if (recovered[i] != 0) goto end;
	}
	em = recovered + offset;
	if (em[em_len - 1] != 0xbc) goto end;

	db_len = em_len - SHA256_DIGEST_SIZE - 1;
	h = em + db_len;
	unused_bits = 8 * em_len - em_bits;
	if (unused_bits > 7) goto end;
	if (unused_bits && (em[0] & (uint8_t)(0xffu << (8 - unused_bits))) != 0) goto end;

	if (rsa_mgf1_sha256(h, SHA256_DIGEST_SIZE, mask, db_len) != 1) goto end;
	for (i = 0; i < db_len; i++) db[i] = em[i] ^ mask[i];
	if (unused_bits) db[0] &= (uint8_t)(0xffu >> unused_bits);

	ps_len = em_len - SHA256_DIGEST_SIZE - SALT_LEN - 2;
	for (i = 0; i < ps_len; i++) {
		if (db[i] != 0) goto end;
	}
	if (db[ps_len] != 0x01) goto end;
	salt = db + ps_len + 1;

	sha256_init(&hash_ctx);
	sha256_update(&hash_ctx, prefix, sizeof(prefix));
	sha256_update(&hash_ctx, dgst, SHA256_DIGEST_SIZE);
	sha256_update(&hash_ctx, salt, SALT_LEN);
	sha256_finish(&hash_ctx, expected_h);
	if (gmssl_secure_memcmp(h, expected_h, SHA256_DIGEST_SIZE) != 0) goto end;
	ret = 1;

end:
	gmssl_secure_clear(recovered, sizeof(recovered));
	gmssl_secure_clear(db, sizeof(db));
	gmssl_secure_clear(mask, sizeof(mask));
	gmssl_secure_clear(expected_h, sizeof(expected_h));
	gmssl_secure_clear(&hash_ctx, sizeof(hash_ctx));
	return ret;
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
