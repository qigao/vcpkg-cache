# Bounded RSA public-key ABI and import for standard TLS authentication.
# Public/private arithmetic is shared in rsa_private_op.c.

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

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
