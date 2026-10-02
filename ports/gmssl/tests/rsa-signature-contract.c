#include <gmssl/hex.h>
#include <gmssl/rsa.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const char public_der_hex[] =
"3082010a0282010100c98c6d1f045ce8b61257fe3964e5ef6a711706776b967f89582914cd166e8447"
"2b6910bf4b920d023fb80b19f82c1e1e7d00bf40bccb0d0bef95c62c7d659e4fd4a89561b19e7ee2"
"538d16ec44775bcd142a690f1543238b82e38378738c932f4aa3e2ad79b568b0128ea7c92ef7d15fa"
"cf2ceea28a3b43e23b541fe072e1dd3587ebdf1ced4a9e8231a63f75c3fc3f4dec581a14576491471"
"838dd24e451751dac76ec3a4950a3f1b56e946060cc3a5bbf581f7253f5b8a3f7fe9c2090e9fe89c"
"9f8d2348f3964c14e3a0ed606e6268fcac337956956f71506c2cd21ec56e269ae59263428e6a82e1"
"e83ec33e0f004fdfb0353e2929424436ca33cb87f479790203010001";

static const char digest_hex[] =
"64a38c93da86ec73ca66b5a24172260f2401316ebabf40c8bfc7004188cac2ad";

static const char pkcs1_sig_hex[] =
"0bb2e4b5a242542106d99bc85bb93682a81b6e900a5a65f05872bf257e2b6b4e417f2e319023e2b4"
"8ef933722f908a00042f308a05363bfd4ab906f82a3e92b7de32a4858454c69d95c29f54bc79a0a8"
"12cce620a26fcb28d8d952af8420ff360efa82d7f63bebd2ebabc5b7b807e2216b2cf20bf081ca24a"
"cef29648669c66d986ee76fd13678145ec09dd85e8ab19058a394b85d288ee8e24beca332010f510c"
"b4b0e80f4d2b4e2a4e92bd1f7c65642c30879c96770f1b4152a5782c3c3ccc9cafe1b2f308fff75a"
"4276eef150d80804cefbcbe9f5606d4f37080f3215da2ad1acd0f5563cdd70a660e596a40ae8b0376"
"e81eb237fa6acbfcdc622a4a65dac";

static const char pss_sig_hex[] =
"81d828555133b07d1961f9491f274483d30cbcf8005337f092801c4abfbdb955aee3d4ee86d54436"
"4854ca150bdff4a7f0efeb45269c10428d11f85b82ac5a0e23bdfa12bdc658d0a7ccf1ae71e709bf"
"69135371661dfd39c4168a558b96d58bc46dc707e6768e4da8911cee9cfee6fcabf3ae6febf0cdc8"
"78eb4637f0c71fe5d9d0373fd4be76a3325a817d0de33ac0251360f0e5a697bf22e008ee01c6c3e7"
"20e85ffe59b99617edd50f2eeb17c40f56ce958acaa6b08ad0b6d97685dea051b9a685df96ce96ef"
"a9b0ea41164ed6a8b96872cc96e557165587141dbc8ae14fd9eafa98ccd8eb21fa9168c008243bf02"
"d01fcc4c69103c1480f50e83dea0a4d";

static int decode(const char *hex, uint8_t *out, size_t expected)
{
	size_t outlen = 0;
	if (hex_to_bytes(hex, strlen(hex), out, &outlen) != 1) return -1;
	return outlen == expected ? 1 : -1;
}

int main(void)
{
	uint8_t der[320];
	uint8_t digest[32];
	uint8_t pkcs1_sig[RSA_MIN_MODULUS_SIZE];
	uint8_t pss_sig[RSA_MIN_MODULUS_SIZE];
	uint8_t bad_digest[32];
	uint8_t bad_sig[RSA_MIN_MODULUS_SIZE];
	size_t der_len = 0;
	const uint8_t *p;
	size_t plen;
	RSA_PUBLIC_KEY key;

	if (hex_to_bytes(public_der_hex, strlen(public_der_hex), der, &der_len) != 1) return 1;
	if (decode(digest_hex, digest, sizeof(digest)) != 1) return 2;
	if (decode(pkcs1_sig_hex, pkcs1_sig, sizeof(pkcs1_sig)) != 1) return 3;
	if (decode(pss_sig_hex, pss_sig, sizeof(pss_sig)) != 1) return 4;

	p = der;
	plen = der_len;
	if (rsa_public_key_from_der(&key, &p, &plen) != 1 || plen != 0) return 5;

	if (rsa_verify_pkcs1_v15_sha256(&key, digest, pkcs1_sig, sizeof(pkcs1_sig)) != 1) return 6;
	if (rsa_verify_pss_sha256(&key, digest, pss_sig, sizeof(pss_sig)) != 1) return 7;

	memcpy(bad_digest, digest, sizeof(bad_digest));
	bad_digest[0] ^= 0x80;
	if (rsa_verify_pkcs1_v15_sha256(&key, bad_digest, pkcs1_sig, sizeof(pkcs1_sig)) != 0) return 8;
	if (rsa_verify_pss_sha256(&key, bad_digest, pss_sig, sizeof(pss_sig)) != 0) return 9;

	memcpy(bad_sig, pkcs1_sig, sizeof(bad_sig));
	bad_sig[sizeof(bad_sig) - 1] ^= 0x01;
	if (rsa_verify_pkcs1_v15_sha256(&key, digest, bad_sig, sizeof(bad_sig)) != 0) return 10;

	memcpy(bad_sig, pss_sig, sizeof(bad_sig));
	bad_sig[sizeof(bad_sig) - 1] ^= 0x01;
	if (rsa_verify_pss_sha256(&key, digest, bad_sig, sizeof(bad_sig)) != 0) return 11;

	puts("GmSSL RSA PKCS#1 v1.5/PSS SHA-256 verification: PASS");
	return 0;
}
