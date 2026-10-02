#include <gmssl/rsa.h>

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
	static const char public_key_der_hex[] =
		"3082010a0282010100b11e65f6f2ee32ea255b791dc4b7d30ea448967496"
		"b563d110280af9f4e927680b5679f5aa3e8fc27806c44265b7e3735b27c14c0"
		"a3450ed72d90bb7116f8c47bc064391e444f31c39d93b8812acd4f7db198a2fa"
		"c39226592467e2704fec42564e1d0fc5253eeefd3b453aa0a4dd1355e74c535f"
		"50836d544db068f98c624a2b6e30032e4c822fc08b2861d73acb13ad343ac7e"
		"81228372697bf386fd6e19ff040bb3725d684d1718ed4b91a04ca81e6497cc19"
		"806fe73e0546032fddc71a1ed5fd76787c2894ccacb5ad7a0d63d8da32e5549"
		"142d824b03fb7d5079406cd1da6d4c0383013759d199d51d519eb6d9a8456e4"
		"1a7b03dd8908dab965501149870203010001";
	static const char digest_hex[] =
		"baf9c67d2a07bb81c345c5514a341ae96d5e182b123580f7c1180e2ab31cde21";
	static const char signature_hex[] =
		"ac4a4e36d1f45e79ec2fbde14e926ccf357e83301c0d6b1cf738e41e366dd5d7"
		"8d0cd0b605bd18feb7e1523fbc78e0719da3e52a5b6004c97accd665759f29f"
		"ddca5a0b9c51d666dd7ec0a83e5f2cb423c59fad789100bd8885f049a0fdf20"
		"8b3b044c37a3891e1e97a7b1bdbc68f24f6ad946694eebdbcf8661a7f84cb7b"
		"dd75fb1dff664e6021fb36d5e53e5320e65bc2188906e7552f67ee659204059a"
		"9c27ad7f95fddc5fc92c939ef9caf0288b24a22674807908a58e5f97780f8d9"
		"4df16388a5b009ae7e708c34c9ea4c84792e1d3bca01459efaf9bf055f1921b"
		"17b9271f4d8707ba1c2507949bb904085da550ef7319271342187e44107f87f5"
		"7b5ae";
	uint8_t der[300];
	uint8_t digest[32];
	uint8_t sig[RSA_MAX_MODULUS_SIZE];
	size_t derlen = 0;
	size_t digestlen = 0;
	size_t siglen = 0;
	const uint8_t *p;
	size_t len;
	RSA_PUBLIC_KEY key;
	int ret;

	if (hex_to_bytes(public_key_der_hex, der, sizeof(der), &derlen) != 1) return 1;
	if (hex_to_bytes(digest_hex, digest, sizeof(digest), &digestlen) != 1 || digestlen != 32) return 2;
	if (hex_to_bytes(signature_hex, sig, sizeof(sig), &siglen) != 1) return 3;

	p = der;
	len = derlen;
	if (rsa_public_key_from_der(&key, &p, &len) != 1 || len != 0) return 4;
	if (key.modulus_size != siglen) return 5;

	ret = rsa_pkcs1_v15_verify_sha256(&key, digest, sig, siglen);
	if (ret != 1) return 6;

	digest[0] ^= 0x01;
	ret = rsa_pkcs1_v15_verify_sha256(&key, digest, sig, siglen);
	digest[0] ^= 0x01;
	if (ret != 0) return 7;

	sig[siglen - 1] ^= 0x01;
	ret = rsa_pkcs1_v15_verify_sha256(&key, digest, sig, siglen);
	if (ret == 1) return 8;

	puts("GmSSL RSA PKCS#1 v1.5 SHA-256 verify contract: PASS");
	return 0;
}
