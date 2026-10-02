# Bounded RSA private-key representation and strict PKCS#1 parser.
# This slice intentionally stops before private modular exponentiation/signing.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
typedef struct {
	size_t modulus_size;
	uint8_t modulus[RSA_MAX_MODULUS_SIZE];
	uint32_t public_exponent;
} RSA_PUBLIC_KEY;
]==]
[==[
typedef struct {
	size_t modulus_size;
	uint8_t modulus[RSA_MAX_MODULUS_SIZE];
	uint32_t public_exponent;
} RSA_PUBLIC_KEY;

#define RSA_MAX_PRIME_SIZE (RSA_MAX_MODULUS_SIZE / 2)

typedef struct {
	RSA_PUBLIC_KEY public_key;
	size_t prime_size;
	uint8_t prime1[RSA_MAX_PRIME_SIZE];
	uint8_t prime2[RSA_MAX_PRIME_SIZE];
	uint8_t exponent1[RSA_MAX_PRIME_SIZE];
	uint8_t exponent2[RSA_MAX_PRIME_SIZE];
	uint8_t coefficient[RSA_MAX_PRIME_SIZE];
} RSA_PRIVATE_KEY;
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_public_key_to_der(const RSA_PUBLIC_KEY *key, uint8_t **out, size_t *outlen);
]==]
[==[
int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
int rsa_public_key_to_der(const RSA_PUBLIC_KEY *key, uint8_t **out, size_t *outlen);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
[==[
static int rsa_private_component_copy(uint8_t *out, size_t outlen,
	const uint8_t *in, size_t inlen)
{
	if (!out || !outlen || !in || !inlen) {
		error_print();
		return -1;
	}
	if (inlen > 1 && in[0] == 0) {
		in++;
		inlen--;
	}
	if (!inlen || inlen > outlen) {
		error_print();
		return -1;
	}
	memset(out, 0, outlen);
	memcpy(out + outlen - inlen, in, inlen);
	return 1;
}

int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen)
{
	const uint8_t *d;
	size_t dlen;
	int version;
	const uint8_t *n;
	size_t nlen;
	int e;
	const uint8_t *private_exponent;
	size_t private_exponent_len;
	const uint8_t *p;
	size_t plen;
	const uint8_t *q;
	size_t qlen;
	const uint8_t *dP;
	size_t dPlen;
	const uint8_t *dQ;
	size_t dQlen;
	const uint8_t *qInv;
	size_t qInvlen;
	uint32_t p_bn[RSA_MAX_PRIME_SIZE / 4];
	uint32_t q_bn[RSA_MAX_PRIME_SIZE / 4];
	uint32_t product[RSA_MAX_MODULUS_WORDS];
	uint32_t exponent1_bn[RSA_MAX_PRIME_SIZE / 4];
	uint32_t exponent2_bn[RSA_MAX_PRIME_SIZE / 4];
	uint32_t coefficient_bn[RSA_MAX_PRIME_SIZE / 4];
	uint8_t product_bytes[RSA_MAX_MODULUS_SIZE];
	size_t k;
	int ret = -1;

	if (!key || !in || !*in || !inlen) {
		error_print();
		return -1;
	}
	memset(key, 0, sizeof(*key));
	memset(p_bn, 0, sizeof(p_bn));
	memset(q_bn, 0, sizeof(q_bn));
	memset(product, 0, sizeof(product));
	memset(exponent1_bn, 0, sizeof(exponent1_bn));
	memset(exponent2_bn, 0, sizeof(exponent2_bn));
	memset(coefficient_bn, 0, sizeof(coefficient_bn));
	memset(product_bytes, 0, sizeof(product_bytes));

	if (asn1_sequence_from_der(&d, &dlen, in, inlen) != 1
		|| asn1_int_from_der(&version, &d, &dlen) != 1
		|| asn1_integer_from_der(&n, &nlen, &d, &dlen) != 1
		|| asn1_int_from_der(&e, &d, &dlen) != 1
		|| asn1_integer_from_der(&private_exponent, &private_exponent_len, &d, &dlen) != 1
		|| asn1_integer_from_der(&p, &plen, &d, &dlen) != 1
		|| asn1_integer_from_der(&q, &qlen, &d, &dlen) != 1
		|| asn1_integer_from_der(&dP, &dPlen, &d, &dlen) != 1
		|| asn1_integer_from_der(&dQ, &dQlen, &d, &dlen) != 1
		|| asn1_integer_from_der(&qInv, &qInvlen, &d, &dlen) != 1
		|| asn1_length_is_zero(dlen) != 1) {
		error_print();
		goto end;
	}
	if (version != 0) {
		error_print();
		goto end;
	}
	if (nlen > 1 && n[0] == 0) {
		n++;
		nlen--;
	}
	if (nlen < RSA_MIN_MODULUS_SIZE
		|| nlen > RSA_MAX_MODULUS_SIZE
		|| (nlen & 7u) != 0
		|| n[0] == 0
		|| (n[nlen - 1] & 1u) == 0
		|| e < 3 || (e & 1) == 0
		|| private_exponent_len == 0 || private_exponent_len > nlen + 1) {
		error_print();
		goto end;
	}

	key->public_key.modulus_size = nlen;
	memcpy(key->public_key.modulus, n, nlen);
	key->public_key.public_exponent = (uint32_t)e;
	key->prime_size = nlen / 2;

	if (rsa_private_component_copy(key->prime1, key->prime_size, p, plen) != 1
		|| rsa_private_component_copy(key->prime2, key->prime_size, q, qlen) != 1
		|| rsa_private_component_copy(key->exponent1, key->prime_size, dP, dPlen) != 1
		|| rsa_private_component_copy(key->exponent2, key->prime_size, dQ, dQlen) != 1
		|| rsa_private_component_copy(key->coefficient, key->prime_size, qInv, qInvlen) != 1) {
		error_print();
		goto end;
	}
	if ((key->prime1[key->prime_size - 1] & 1u) == 0
		|| (key->prime2[key->prime_size - 1] & 1u) == 0
		|| key->prime1[0] == 0 || key->prime2[0] == 0) {
		error_print();
		goto end;
	}

	k = key->prime_size / 4;
	bn_from_bytes(p_bn, k, key->prime1);
	bn_from_bytes(q_bn, k, key->prime2);
	bn_from_bytes(exponent1_bn, k, key->exponent1);
	bn_from_bytes(exponent2_bn, k, key->exponent2);
	bn_from_bytes(coefficient_bn, k, key->coefficient);
	if (bn_cmp(p_bn, q_bn, k) == 0
		|| bn_is_zero(exponent1_bn, k)
		|| bn_cmp(exponent1_bn, p_bn, k) >= 0
		|| bn_is_zero(exponent2_bn, k)
		|| bn_cmp(exponent2_bn, q_bn, k) >= 0
		|| bn_is_zero(coefficient_bn, k)
		|| bn_cmp(coefficient_bn, p_bn, k) >= 0) {
		error_print();
		goto end;
	}
	bn_mul(product, p_bn, q_bn, k);
	bn_to_bytes(product, k * 2, product_bytes);
	if (gmssl_secure_memcmp(product_bytes,
		key->public_key.modulus, key->public_key.modulus_size) != 0) {
		error_print();
		goto end;
	}

	ret = 1;

end:
	if (ret != 1) {
		gmssl_secure_clear(key, sizeof(*key));
	}
	gmssl_secure_clear(p_bn, sizeof(p_bn));
	gmssl_secure_clear(q_bn, sizeof(q_bn));
	gmssl_secure_clear(product, sizeof(product));
	gmssl_secure_clear(exponent1_bn, sizeof(exponent1_bn));
	gmssl_secure_clear(exponent2_bn, sizeof(exponent2_bn));
	gmssl_secure_clear(coefficient_bn, sizeof(coefficient_bn));
	gmssl_secure_clear(product_bytes, sizeof(product_bytes));
	return ret;
}

void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key)
{
	if (key) {
		gmssl_secure_clear(key, sizeof(*key));
	}
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
