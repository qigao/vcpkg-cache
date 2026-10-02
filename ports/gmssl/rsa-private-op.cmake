# Efficient bounded RSA private CRT operation.
# Uses the existing GmSSL Barrett exponentiation after computing the reciprocal
# for each arbitrary RSA prime with bounded restoring division.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
[==[
int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen);
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
[==[
static void rsa_bn_lshift1(uint32_t *a, size_t k)
{
	uint32_t carry = 0;
	size_t i;
	for (i = 0; i < k; i++) {
		uint32_t next = a[i] >> 31;
		a[i] = (a[i] << 1) | carry;
		carry = next;
	}
}

static int rsa_barrett_precompute(uint32_t *u, const uint32_t *p, size_t k)
{
	uint32_t rem[RSA_MAX_PRIME_SIZE / 4 + 1];
	uint32_t p_ext[RSA_MAX_PRIME_SIZE / 4 + 1];
	size_t bit;
	size_t top_bit;

	if (!u || !p || !k || k > RSA_MAX_PRIME_SIZE / 4 || (p[0] & 1u) == 0) {
		error_print();
		return -1;
	}
	memset(u, 0, (k + 1) * sizeof(uint32_t));
	memset(rem, 0, sizeof(rem));
	memset(p_ext, 0, sizeof(p_ext));
	memcpy(p_ext, p, k * sizeof(uint32_t));

	top_bit = 64 * k;
	bit = top_bit;
	for (;;) {
		rsa_bn_lshift1(rem, k + 1);
		if (bit == top_bit) {
			rem[0] |= 1u;
		}
		if (bn_cmp(rem, p_ext, k + 1) >= 0) {
			size_t word = bit / 32;
			size_t shift = bit % 32;
			bn_sub(rem, rem, p_ext, k + 1);
			if (word > k) {
				error_print();
				gmssl_secure_clear(rem, sizeof(rem));
				gmssl_secure_clear(p_ext, sizeof(p_ext));
				return -1;
			}
			u[word] |= (uint32_t)1u << shift;
		}
		if (bit == 0) break;
		bit--;
	}

	gmssl_secure_clear(rem, sizeof(rem));
	gmssl_secure_clear(p_ext, sizeof(p_ext));
	return 1;
}

static int rsa_mod_from_bytes(uint32_t *r,
	const uint8_t *in, size_t inlen,
	const uint32_t *p, size_t k)
{
	uint32_t one[RSA_MAX_PRIME_SIZE / 4];
	size_t i;
	int bit;

	if (!r || !in || !p || !k || k > RSA_MAX_PRIME_SIZE / 4) {
		error_print();
		return -1;
	}
	bn_set_word(r, 0, k);
	bn_set_word(one, 1, k);
	for (i = 0; i < inlen; i++) {
		for (bit = 7; bit >= 0; bit--) {
			bn_mod_add(r, r, r, p, k);
			if ((in[i] >> bit) & 1u) {
				bn_mod_add(r, r, one, p, k);
			}
		}
	}
	gmssl_secure_clear(one, sizeof(one));
	return 1;
}

int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen)
{
	enum { MAX_K = RSA_MAX_PRIME_SIZE / 4 };
	uint32_t p[MAX_K];
	uint32_t q[MAX_K];
	uint32_t dP[MAX_K];
	uint32_t dQ[MAX_K];
	uint32_t qInv[MAX_K];
	uint32_t uP[MAX_K + 1];
	uint32_t uQ[MAX_K + 1];
	uint32_t cP[MAX_K];
	uint32_t cQ[MAX_K];
	uint32_t m1[MAX_K];
	uint32_t m2[MAX_K];
	uint32_t m2_mod_p[MAX_K];
	uint32_t diff[MAX_K];
	uint32_t h[MAX_K];
	uint32_t result[RSA_MAX_MODULUS_WORDS];
	uint32_t modulus[RSA_MAX_MODULUS_WORDS];
	uint32_t tmp[7 * MAX_K + 4];
	uint8_t m2_bytes[RSA_MAX_PRIME_SIZE];
	size_t k;
	size_t i;
	uint64_t carry;
	int ret = -1;

	if (outlen) *outlen = 0;
	if (!key || !in || !out || !outlen
		|| key->public_key.modulus_size < RSA_MIN_MODULUS_SIZE
		|| key->public_key.modulus_size > RSA_MAX_MODULUS_SIZE
		|| key->prime_size * 2 != key->public_key.modulus_size
		|| (key->prime_size & 3u) != 0
		|| inlen != key->public_key.modulus_size
		|| outmax < key->public_key.modulus_size) {
		error_print();
		return -1;
	}

	memset(p, 0, sizeof(p));
	memset(q, 0, sizeof(q));
	memset(dP, 0, sizeof(dP));
	memset(dQ, 0, sizeof(dQ));
	memset(qInv, 0, sizeof(qInv));
	memset(uP, 0, sizeof(uP));
	memset(uQ, 0, sizeof(uQ));
	memset(cP, 0, sizeof(cP));
	memset(cQ, 0, sizeof(cQ));
	memset(m1, 0, sizeof(m1));
	memset(m2, 0, sizeof(m2));
	memset(m2_mod_p, 0, sizeof(m2_mod_p));
	memset(diff, 0, sizeof(diff));
	memset(h, 0, sizeof(h));
	memset(result, 0, sizeof(result));
	memset(modulus, 0, sizeof(modulus));
	memset(tmp, 0, sizeof(tmp));
	memset(m2_bytes, 0, sizeof(m2_bytes));

	k = key->prime_size / 4;
	bn_from_bytes(p, k, key->prime1);
	bn_from_bytes(q, k, key->prime2);
	bn_from_bytes(dP, k, key->exponent1);
	bn_from_bytes(dQ, k, key->exponent2);
	bn_from_bytes(qInv, k, key->coefficient);
	bn_from_bytes(modulus, k * 2, key->public_key.modulus);

	if (rsa_barrett_precompute(uP, p, k) != 1
		|| rsa_barrett_precompute(uQ, q, k) != 1
		|| rsa_mod_from_bytes(cP, in, inlen, p, k) != 1
		|| rsa_mod_from_bytes(cQ, in, inlen, q, k) != 1) {
		error_print();
		goto end;
	}

	bn_barrett_mod_exp(m1, cP, dP, p, uP, tmp, k);
	memset(tmp, 0, sizeof(tmp));
	bn_barrett_mod_exp(m2, cQ, dQ, q, uQ, tmp, k);

	bn_to_bytes(m2, k, m2_bytes);
	if (rsa_mod_from_bytes(m2_mod_p, m2_bytes, key->prime_size, p, k) != 1) {
		error_print();
		goto end;
	}
	bn_mod_sub(diff, m1, m2_mod_p, p, k);
	memset(tmp, 0, sizeof(tmp));
	bn_barrett_mod_mul(h, qInv, diff, p, uP, tmp, k);

	bn_mul(result, q, h, k);
	carry = 0;
	for (i = 0; i < k; i++) {
		uint64_t w = (uint64_t)result[i] + m2[i] + carry;
		result[i] = (uint32_t)w;
		carry = w >> 32;
	}
	for (i = k; carry && i < 2 * k; i++) {
		uint64_t w = (uint64_t)result[i] + carry;
		result[i] = (uint32_t)w;
		carry = w >> 32;
	}
	if (carry || bn_cmp(result, modulus, 2 * k) >= 0) {
		error_print();
		goto end;
	}

	bn_to_bytes(result, 2 * k, out);
	*outlen = key->public_key.modulus_size;
	ret = 1;

end:
	gmssl_secure_clear(p, sizeof(p));
	gmssl_secure_clear(q, sizeof(q));
	gmssl_secure_clear(dP, sizeof(dP));
	gmssl_secure_clear(dQ, sizeof(dQ));
	gmssl_secure_clear(qInv, sizeof(qInv));
	gmssl_secure_clear(uP, sizeof(uP));
	gmssl_secure_clear(uQ, sizeof(uQ));
	gmssl_secure_clear(cP, sizeof(cP));
	gmssl_secure_clear(cQ, sizeof(cQ));
	gmssl_secure_clear(m1, sizeof(m1));
	gmssl_secure_clear(m2, sizeof(m2));
	gmssl_secure_clear(m2_mod_p, sizeof(m2_mod_p));
	gmssl_secure_clear(diff, sizeof(diff));
	gmssl_secure_clear(h, sizeof(h));
	gmssl_secure_clear(result, sizeof(result));
	gmssl_secure_clear(modulus, sizeof(modulus));
	gmssl_secure_clear(tmp, sizeof(tmp));
	gmssl_secure_clear(m2_bytes, sizeof(m2_bytes));
	return ret;
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
