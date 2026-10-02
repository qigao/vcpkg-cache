#include <gmssl/hex.h>
#include <gmssl/rsa.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const char rsa_public_der_hex[] =
"3082010a0282010100b307505ec3ea226b39c629e02edf201079bdef38d549b7044a1f743ec421c021"
"c9181dd80c6e0c986576978e334832746a329113ea20bdee634e8f607842f954aa41800092c5a10d0"
"da5cbd1f3b82d794320958594f95355e3ea8cd84ed5f4420d62bbfe20256d3bdb9ed1f3f051310487"
"962e12d080439fbb6fea653236b9f8bcf55a147a7183826076e288a943ff42a6cce775ed170e1c235"
"b577ffbf0109a054181112d19717f47f0ad7563fd6c53e9caf100853c1b412ce107dd1bd9e08b27cb"
"77884e4b5b3d3dafcdad97d478f2588b45009222163c1ba2fb16efbf6c2f87ba416e9c782c34215aa"
"dabbc8e8b491bf7d2de2399a284ce76683aa0f5a7490203010001";

static const char representative_hex[] =
"125ca5ee3780c9125ba4ed367fc8115aa3ec357ec71059a2eb347dc60f58a1ea337cc50e57a0e932"
"7bc40d569fe8317ac30c559ee73079c20b549de62f78c10a539ce52e77c009529be42d76bf08519a"
"e32c75be075099e22b74bd064f98e12a73bc054e97e02972bb044d96df2871ba034c95de2770b902"
"4b94dd266fb8014a93dc256eb7004992db246db6ff4891da236cb5fe4790d9226bb4fd468fd8216a"
"b3fc458ed72069b2fb448dd61f68b1fa438cd51e67b0f9428bd41d66aff8418ad31c65aef74089d"
"21b64adf63f88d11a63acf53e87d01962abf43d86cf1861aaf33c85ce1760a9f23b84cd165fa8f"
"13a83cc155ea7f03982cb145da6ef3881ca";

static const char expected_hex[] =
"56bad7826f21f243f2e968294da219daa1107a22e87e422f2f8541b8ee4f2d2ca258a705e923692"
"6c35b48b93ea2e4e2d10e409b1eed7270aa48524f14f98bab80dd88bc5eaeafc87fa58f71da5936"
"5a3b55f83c26466484f66a710e55e50fb21725c598da8ac321333f06504c8b54634d1d7e19ea59d"
"5a3533347191916e80c0cafad89f9581dffb9c417a965f7d066dfe4db31c657cc0338e134e76f996"
"cb286e7ed1f094bab817803fb104a760eeb92559ea521938faecf80e3aee53ecc7de9ce143ab56bb"
"5e5f39ae73a7eb2c2417d2f5aaf7fea3530c33659bf73b92f7235a15377fdb2ba690fdff80bde7c"
"14d6978659fe45903e7e165bbd8bd57cec67";

static int decode(const char *hex, uint8_t *out, size_t expected_len)
{
	size_t outlen = 0;
	if (hex_to_bytes(hex, strlen(hex), out, &outlen) != 1) return -1;
	return outlen == expected_len ? 1 : -1;
}

int main(void)
{
	uint8_t der[320];
	uint8_t representative[RSA_MIN_MODULUS_SIZE];
	uint8_t expected[RSA_MIN_MODULUS_SIZE];
	uint8_t output[RSA_MAX_MODULUS_SIZE];
	size_t der_len = 0;
	size_t output_len = 0;
	const uint8_t *p;
	size_t plen;
	RSA_PUBLIC_KEY key;

	if (hex_to_bytes(rsa_public_der_hex, strlen(rsa_public_der_hex), der, &der_len) != 1) return 1;
	if (decode(representative_hex, representative, sizeof(representative)) != 1) return 2;
	if (decode(expected_hex, expected, sizeof(expected)) != 1) return 3;

	p = der;
	plen = der_len;
	if (rsa_public_key_from_der(&key, &p, &plen) != 1 || plen != 0) return 4;
	if (key.modulus_size != RSA_MIN_MODULUS_SIZE || key.public_exponent != 65537u) return 5;

	if (rsa_public_key_operation(&key, representative, sizeof(representative),
			output, sizeof(output), &output_len) != 1) return 6;
	if (output_len != sizeof(expected) || memcmp(output, expected, sizeof(expected)) != 0) return 7;

	/* The representative must be strictly smaller than n. */
	if (rsa_public_key_operation(&key, key.modulus, key.modulus_size,
			output, sizeof(output), &output_len) == 1) return 8;

	puts("GmSSL bounded RSA public operation: PASS");
	return 0;
}
