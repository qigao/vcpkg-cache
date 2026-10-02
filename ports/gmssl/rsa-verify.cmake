# Minimal bounded RSA public-key primitive for standard TLS authentication.
#
# This is intentionally below X.509/TLS. It establishes a standalone,
# dependency-free correctness gate before signature-scheme integration.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

vcpkg_replace_string(
    "${_gmssl_rsa_h}"
    "int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);"
    "#define RSA_MIN_MODULUS_SIZE 256\n#define RSA_MAX_MODULUS_SIZE 512\n#define RSA_MAX_MODULUS_WORDS (RSA_MAX_MODULUS_SIZE / 4)\n\ntypedef struct {\n\tsize_t modulus_size;\n\tuint8_t modulus[RSA_MAX_MODULUS_SIZE];\n\tuint32_t public_exponent;\n} RSA_PUBLIC_KEY;\n\nint rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);\nint rsa_public_key_operation(const RSA_PUBLIC_KEY *key,\n\tconst uint8_t *in, size_t inlen,\n\tuint8_t *out, size_t outmax, size_t *outlen);\nint rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "#include <gmssl/rsa.h>\n#include <gmssl/asn1.h>"
    "#include <gmssl/rsa.h>\n#include <gmssl/bn.h>\n#include <gmssl/mem.h>\n#include <gmssl/asn1.h>"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)\n{"
    [==[
static void rsa_mod_mul(uint32_t *r,
	const uint32_t *a, const uint32_t *b,
	const uint32_t *n, size_t k)
{
	uint32_t acc[RSA_MAX_MODULUS_WORDS];
	uint32_t x[RSA_MAX_MODULUS_WORDS];
	size_t i;
	int bit;

	bn_set_word(acc, 0, k);
	bn_copy(x, a, k);
	for (i = 0; i < k; i++) {
		uint32_t word = b[i];
		for (bit = 0; bit < 32; bit++) {
			if (word & 1u) {
				bn_mod_add(acc, acc, x, n, k);
			}
			word >>= 1;
			bn_mod_add(x, x, x, n, k);
		}
	}
	bn_copy(r, acc, k);
	gmssl_secure_clear(acc, sizeof(acc));
	gmssl_secure_clear(x, sizeof(x));
}

int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen)
{
	const uint8_t *d;
	size_t dlen;
	const uint8_t *modulus;
	size_t modulus_len;
	int exponent;

	if (!key || !in || !inlen) {
		error_print();
		return -1;
	}
	memset(key, 0, sizeof(*key));
	if (asn1_sequence_from_der(&d, &dlen, in, inlen) != 1
		|| asn1_integer_from_der(&modulus, &modulus_len, &d, &dlen) != 1
		|| asn1_int_from_der(&exponent, &d, &dlen) != 1
		|| asn1_length_is_zero(dlen) != 1) {
		error_print();
		return -1;
	}
	/* DER INTEGER may carry one sign-padding zero for a positive modulus. */
	if (modulus_len > 1 && modulus[0] == 0) {
		modulus++;
		modulus_len--;
	}
	if (modulus_len < RSA_MIN_MODULUS_SIZE
		|| modulus_len > RSA_MAX_MODULUS_SIZE
		|| (modulus_len & 3u) != 0
		|| modulus[0] == 0
		|| (modulus[modulus_len - 1] & 1u) == 0
		|| exponent < 3
		|| (exponent & 1) == 0) {
		error_print();
		return -1;
	}
	key->modulus_size = modulus_len;
	memcpy(key->modulus, modulus, modulus_len);
	key->public_exponent = (uint32_t)exponent;
	return 1;
}

int rsa_public_key_operation(const RSA_PUBLIC_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen)
{
	uint32_t modulus[RSA_MAX_MODULUS_WORDS];
	uint32_t base[RSA_MAX_MODULUS_WORDS];
	uint32_t result[RSA_MAX_MODULUS_WORDS];
	size_t k;
	uint32_t exponent;
	int ret = -1;

	if (outlen) *outlen = 0;
	if (!key || !in || !out || !outlen
		|| key->modulus_size < RSA_MIN_MODULUS_SIZE
		|| key->modulus_size > RSA_MAX_MODULUS_SIZE
		|| (key->modulus_size & 3u) != 0
		|| inlen != key->modulus_size
		|| outmax < key->modulus_size
		|| key->public_exponent < 3
		|| (key->public_exponent & 1u) == 0) {
		error_print();
		return -1;
	}

	k = key->modulus_size / 4;
	bn_from_bytes(modulus, k, key->modulus);
	bn_from_bytes(base, k, in);
	if (bn_cmp(base, modulus, k) >= 0) {
		error_print();
		goto end;
	}

	bn_set_word(result, 1, k);
	exponent = key->public_exponent;
	while (exponent) {
		if (exponent & 1u) {
			rsa_mod_mul(result, result, base, modulus, k);
		}
		exponent >>= 1;
		if (exponent) {
			rsa_mod_mul(base, base, base, modulus, k);
		}
	}

	bn_to_bytes(result, k, out);
	*outlen = key->modulus_size;
	ret = 1;

end:
	gmssl_secure_clear(modulus, sizeof(modulus));
	gmssl_secure_clear(base, sizeof(base));
	gmssl_secure_clear(result, sizeof(result));
	return ret;
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
