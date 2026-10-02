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
	size_t n = strlen(hex);
	size_t i;
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
	static const char rsa_private_der_hex[] =
		"308204a20201000282010100b3a1c859d3cafca33e5c4daee39dc681632e7af3e379c7d84b976c1fde598816"
		"c58e27605226fcaf0cf0add53db1586cf0b1d2875d78837fdad786a4bbed29db799ff369464e8e71fba5fe0d"
		"259b859ed038b6f68353a87000f9da393bfd22a4eee2d9d5d67a035c88c15978ebaf733170d77af571b4f6f9"
		"5e36efb4af274c6304c7eb3986a6234b4d1bdc0c1349cfc793f468a26d4fd697d769017e91dd74ea5a7ab48e"
		"47305f1bb804e95bec5f8373167959238d23639569b89c410de0ae9e093057b768d54afc8d64151ab6d993d42"
		"2dfbb89da9155a3477b969a1db0fc6912fb8bf0b6532341bce1617604f4cbbfa0d71a59b37881785749c0c195"
		"d1a94d02030100010282010003adc45ace986c21c864ff34488b67d028e0aaa4f45b7f491737392ad294c126e"
		"791d88d98f11d20aaa257dfb39d3e588624bb7bde8c041ebf5e7043f9bdf580535680177fadf12de014fa05ce"
		"92324e2fd3d184c2936e877e059fe9fc7d5bd31be4aa7313803931bbc7eb40ab8c52cec83c5428d2ff7d455b2"
		"018904f3bfdf79faa7b3c5d014e0a14db005dc8d435d9752c9b27445c29e0793d4dbd277bf8654079d56ff6d"
		"b62e34c46d48ddf886697631eab4d46f8facdbb90de6e7cf36906860f46e707cf0592e0437ccf7eb0688548d8"
		"91f30a50d31192d8d688118cadf3c1c3fec871aac471de708da462e32beedecf6eba43c72cd64fe3f736702b1"
		"ac102818100eff2e0556607039ea8e0578d12433343b16353da4cb2570ecd6478bc947b06ba48298459e1b413"
		"4324ca538e16a65ac892275f3a5e6679cc07f86ff1704f635a416f877ac9871f81f204d5ef9441738396f9be3"
		"b1e0fbd869c009957adc037c760b5cab9dbd3dfff6a6b9e409e65aaaf69afc84618f556fbe833f1cd6886a8e1"
		"02818100bfa5fb2f5bd84deaf803765bdf0b401a673e559fe125215131dc4affbeed26861e40edbd62660f81a1"
		"ab26e242437b8cb8c310e7a2d8ee3a7b4a3c233a676e9047f74ec376e41c6e250bd1365b5b563152ac64f3a4"
		"160256fcd8a9fd375f23faeb61b85b4b2e97799817f7dd053d9fa405811e514e42d583f4d5726ee81c71ed02"
		"818066ba5ae4f4eb67d75381c8b9f2e9a65702e8fd8b666eabeb0070556897411c9e402ad6290d026584c7897"
		"fc0435e315bd186ddb4459a25e6fe3a94e28f2ccde264457581522a7188d6aecf50e4ee28a05bd0cc6acef1fa"
		"38592dc078d3408a20e7fcacb069b70a1d75d86146550a3dcb1fba4c4a0681731e2249aaea4027f6c1028180"
		"680f76f93b1493124f8289c4ceb22c276a01d5ba4f24bb177c4c5248d561ad764b7d13d9ae511e8053c93bfec"
		"4de217ac263e08cf5c6766c38bf9131cba797c82ddb61e00e7143e2a6a8e8fb6bd5875296c256ba58513f09fe"
		"96a28e847f5b69065ff41b5612415b5bb33ff9b9bbc12fed713386104987e7f38be66bc40a95ed0281802df50"
		"b8fa59b16439ac7eba78a3d5bd1383d86e4fdc1efa81a4a2959feb2ebfbd711a96039794fca26e1ed478a060"
		"a44591438f4ac768b7f5ad0bde9ca274f03c7d4a48eed05f8964e3342d2211519ee3ab58adc320b12c09a6e77"
		"30600f45f74b5ff7a0d0682edc0653f42ca4c813523d49d84a11e42859a5e66865383f1f4f";
	static const char expected_private_42_hex[] =
		"9428f77326f4d21f9ff676173620c866ec2192fda29fcbcd2d89893a40530922962d1b93528773e3dd4a983954e5f9ce"
		"adb63ef5b40ddd612a2be949c6f6ffc17c123c9ade583cab46139b787c6a825a711a35afff96e9929145bdcabe7b83e81"
		"be3cbad6bbca9c230e7914596df2f5fd234b0526110409daab31306ac8fb10128cc104295293b7bae9c1d0bdfeaf75a2"
		"527c6bfae55dbbb1448dcc96f89a197afe439ea9b8bfe7aa6da0f21023703b2da11783f016a880c71180a583ed52c368"
		"bf9416117235d3f374eafa36ac33eef99dfe2ac094e36d416ec3de61aa67f7c9a32987e30eb590fb01c4c527f316261c"
		"4347cd33be9836cfb85ac742348585d";
	uint8_t der[1280];
	uint8_t representative[RSA_MAX_MODULUS_SIZE] = {0};
	uint8_t signature[RSA_MAX_MODULUS_SIZE] = {0};
	uint8_t expected[RSA_MAX_MODULUS_SIZE] = {0};
	uint8_t recovered[RSA_MAX_MODULUS_SIZE] = {0};
	size_t derlen = 0;
	size_t expected_len = 0;
	size_t signature_len = 0;
	size_t recovered_len = 0;
	const uint8_t *p;
	size_t len;
	RSA_PRIVATE_KEY key;

	if (hex_to_bytes(rsa_private_der_hex, der, sizeof(der), &derlen) != 1) return 1;
	if (hex_to_bytes(expected_private_42_hex, expected, sizeof(expected), &expected_len) != 1
		|| expected_len != 256u) return 2;
	p = der;
	len = derlen;
	if (rsa_private_key_from_der(&key, &p, &len) != 1 || len != 0) return 3;

	representative[key.public_key.modulus_size - 1] = 42u;
	if (rsa_private_key_operation(&key,
		representative, key.public_key.modulus_size,
		signature, sizeof(signature), &signature_len) != 1) return 4;
	if (signature_len != expected_len
		|| memcmp(signature, expected, expected_len) != 0) return 5;

	if (rsa_public_key_operation(&key.public_key,
		signature, signature_len,
		recovered, sizeof(recovered), &recovered_len) != 1) return 6;
	if (recovered_len != key.public_key.modulus_size
		|| memcmp(recovered, representative, recovered_len) != 0) return 7;

	rsa_private_key_cleanup(&key);
	puts("GmSSL bounded RSA CRT private operation: PASS");
	return 0;
}
