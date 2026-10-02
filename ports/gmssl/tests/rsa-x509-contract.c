#include <gmssl/x509_key.h>
#include <gmssl/tls.h>

#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int hex_nibble(char c)
{
	if (c >= '0' && c <= '9') return c - '0';
	if (c >= 'a' && c <= 'f') return c - 'a' + 10;
	if (c >= 'A' && c <= 'F') return c - 'A' + 10;
	return -1;
}

static int hex_to_bytes(const char *hex, uint8_t *out, size_t outmax, size_t *outlen)
{
	size_t n;
	size_t i;
	if (!hex || !out || !outlen) return -1;
	n = strlen(hex);
	if ((n & 1u) != 0 || n / 2 > outmax) return -1;
	for (i = 0; i < n / 2; i++) {
		int hi = hex_nibble(hex[i * 2]);
		int lo = hex_nibble(hex[i * 2 + 1]);
		if (hi < 0 || lo < 0) return -1;
		out[i] = (uint8_t)((hi << 4) | lo);
	}
	*outlen = n / 2;
	return 1;
}

int main(void)
{
	static const char spki_hex[] =
		"30820122300d06092a864886f70d01010105000382010f003082010a0282010100"
		"b11e65f6f2ee32ea255b791dc4b7d30ea448967496b563d110280af9f4e92768"
		"0b5679f5aa3e8fc27806c44265b7e3735b27c14c0a3450ed72d90bb7116f8c4"
		"7bc064391e444f31c39d93b8812acd4f7db198a2fac39226592467e2704fec42"
		"564e1d0fc5253eeefd3b453aa0a4dd1355e74c535f50836d544db068f98c624"
		"a2b6e30032e4c822fc08b2861d73acb13ad343ac7e81228372697bf386fd6e1"
		"9ff040bb3725d684d1718ed4b91a04ca81e6497cc19806fe73e0546032fddc71"
		"a1ed5fd76787c2894ccacb5ad7a0d63d8da32e5549142d824b03fb7d5079406"
		"cd1da6d4c0383013759d199d51d519eb6d9a8456e41a7b03dd8908dab965501"
		"149870203010001";
	uint8_t spki[320];
	uint8_t encoded[320];
	uint8_t digest[32];
	size_t spki_len = 0;
	size_t encoded_len = 0;
	const uint8_t *p;
	uint8_t *outp;
	size_t len;
	X509_KEY key;
	X509_KEY reparsed;

	if (sizeof(TLS_CTX) != tls_ctx_sizeof() || sizeof(TLS_CONNECT) != tls_connect_sizeof()) return 10;
	if (hex_to_bytes(spki_hex, spki, sizeof(spki), &spki_len) != 1) return 1;

	p = spki;
	len = spki_len;
	if (x509_public_key_info_from_der(&key, &p, &len) != 1 || len != 0) return 2;
	if (key.algor != OID_rsa_encryption || key.algor_param != OID_undef) return 3;
	if (key.u.rsa_public_key.modulus_size != 256
		|| key.u.rsa_public_key.public_exponent != 65537u) return 4;

	outp = encoded;
	if (x509_public_key_info_to_der(&key, &outp, &encoded_len) != 1) return 5;
	if (encoded_len != spki_len || memcmp(encoded, spki, spki_len) != 0) return 6;

	p = encoded;
	len = encoded_len;
	if (x509_public_key_info_from_der(&reparsed, &p, &len) != 1 || len != 0) return 7;
	if (x509_public_key_equ(&key, &reparsed) != 1) return 8;
	if (x509_public_key_digest(&key, digest) != 1) return 9;

	x509_key_cleanup(&reparsed);
	x509_key_cleanup(&key);
	puts("GmSSL RSA SubjectPublicKeyInfo contract: PASS");
	return 0;
}
