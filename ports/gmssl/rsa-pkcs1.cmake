# RSA PKCS#1 v1.5 SHA-256 verification on top of the bounded raw public
# operation. This remains below X.509/TLS so it can be qualified independently.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_public_key_operation(const RSA_PUBLIC_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);
]==]
[==[
int rsa_public_key_operation(const RSA_PUBLIC_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
int rsa_pkcs1_v15_verify_sha256(const RSA_PUBLIC_KEY *key,
	const uint8_t digest[32], const uint8_t *sig, size_t siglen);
int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *d, size_t dlen);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
[==[
int rsa_pkcs1_v15_verify_sha256(const RSA_PUBLIC_KEY *key,
	const uint8_t digest[32], const uint8_t *sig, size_t siglen)
{
	static const uint8_t sha256_digest_info_prefix[] = {
		0x30, 0x31,
		0x30, 0x0d,
		0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01,
		0x05, 0x00,
		0x04, 0x20
	};
	uint8_t em[RSA_MAX_MODULUS_SIZE];
	size_t emlen = 0;
	size_t i;
	int ret = 0;

	if (!key || !digest || !sig
		|| siglen != key->modulus_size
		|| key->modulus_size < RSA_MIN_MODULUS_SIZE
		|| key->modulus_size > RSA_MAX_MODULUS_SIZE) {
		error_print();
		return -1;
	}
	if (rsa_public_key_operation(key, sig, siglen, em, sizeof(em), &emlen) != 1) {
		error_print();
		return -1;
	}
	if (emlen != key->modulus_size || emlen < 11 + sizeof(sha256_digest_info_prefix) + 32) {
		goto end;
	}
	if (em[0] != 0x00 || em[1] != 0x01) {
		goto end;
	}
	i = 2;
	while (i < emlen && em[i] == 0xff) {
		i++;
	}
	/* RFC 8017 requires at least eight 0xff octets. */
	if (i < 10 || i >= emlen || em[i] != 0x00) {
		goto end;
	}
	i++;
	if (emlen - i != sizeof(sha256_digest_info_prefix) + 32) {
		goto end;
	}
	if (memcmp(em + i, sha256_digest_info_prefix,
		sizeof(sha256_digest_info_prefix)) != 0) {
		goto end;
	}
	i += sizeof(sha256_digest_info_prefix);
	if (memcmp(em + i, digest, 32) != 0) {
		goto end;
	}
	ret = 1;

end:
	gmssl_secure_clear(em, sizeof(em));
	return ret;
}

int rsa_public_key_print(FILE *fp, int fmt, int ind, const char *label, const uint8_t *a, size_t alen)
{
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
