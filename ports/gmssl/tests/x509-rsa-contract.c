#include <gmssl/hex.h>
#include <gmssl/x509_cer.h>
#include <gmssl/x509_key.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

static const char spki_hex[] =
"30820122300d06092a864886f70d01010105000382010f003082010a0282010100939b5101c8dfa3ebfcc238791140eb"
"44da0465d1430a8e842d7081ad0c48c6dad64904900011d774bc029171a6747a05795298b5f7043ef4141fae8e21649f"
"f2abed064aaf7fe322d0edd5821107632548fb39c43650cf604a2cef7e28515c61b251c199a1e2cd90f54b4c69ca46b2"
"00d283494b9274211bb1898dae551ad9ee773f6cb98bce2cc30ae9cd4bd0f541652eb87619edb35435185b23b12b5029"
"f86718ff27ed3f695b41b3e86c0b8328af6d15fa5591bf033f5dfcb141926bdbbf142a9aadd82b1bf2c5a9f8625657bb"
"9149b5a0ad6bf50ba95b4833d52b99efab4f47e75b9c342d9a7879947221318529254004b7e5e755a63ac3a274aaacf7"
"ab0203010001";

static const char signature_hex[] =
"495d713aef07713922bb322601b7c488b7be14f4facccf11fb07acaeb3619772d02e355dc615d4b04b38a6b40aa3ccd3"
"a8b3065156a05db69cbded930d4ac4d7cec959984dec587b0f2030922c2d596f0cb8073d0a40eac7cc80797bd8aee9a4"
"51225279fe532b0807f9515f055ce8221b1eddfdb6d8a14e35e1c46d864df31ca96f0d4599f773d97cd5ef73cb955d30"
"7d5db31e1a66318b7bc4bae4751a432280cf7877ff0f8b31f8f214bf1a5086163c3fa74b2df5fce2309270be92a02c20"
"488cd54c714f1af116a1a5f901f766da92a9d4380e5bbda381514f29ccc41402e681db1045386ea1aaf3c29342855541"
"67eba5986223f237e8d7fa28eff33667";

static const char cert_hex[] =
"308202cb308201b3a003020102020101300d06092a864886f70d01010b0500301d311b301906035504030c12676d7373"
"6c2d7273612d636f6e7472616374301e170d3236303130313030303030305a170d3335313233303030303030305a301d"
"311b301906035504030c12676d73736c2d7273612d636f6e747261637430820122300d06092a864886f70d0101010500"
"0382010f003082010a0282010100939b5101c8dfa3ebfcc238791140eb44da0465d1430a8e842d7081ad0c48c6dad649"
"04900011d774bc029171a6747a05795298b5f7043ef4141fae8e21649ff2abed064aaf7fe322d0edd5821107632548fb"
"39c43650cf604a2cef7e28515c61b251c199a1e2cd90f54b4c69ca46b200d283494b9274211bb1898dae551ad9ee773f"
"6cb98bce2cc30ae9cd4bd0f541652eb87619edb35435185b23b12b5029f86718ff27ed3f695b41b3e86c0b8328af6d15"
"fa5591bf033f5dfcb141926bdbbf142a9aadd82b1bf2c5a9f8625657bb9149b5a0ad6bf50ba95b4833d52b99efab4f47"
"e75b9c342d9a7879947221318529254004b7e5e755a63ac3a274aaacf7ab0203010001a316301430120603551d130101"
"ff040830060101ff020100300d06092a864886f70d01010b0500038201010007a7154256c38962c441a6236955e1de82"
"b9d309c72a25862093cc115ae07efbcee0f1bc0ca97f4a7188d23ed75fe794e24f35f1fc855e7f8a37b67c5963a1fe6b"
"320d4fc134fa1ac9b148788a2e70eb8a3b92b9063ec16bd60b79ef3ec4e17b983f2d8b86a0e3174d7eaf1b76e1314604"
"1eb2a019fe5117b734581a53e25afd88d717648cef350f26cb41d81570ba7375f53d6f3dff3b4ef1e13b0d0b6ea73ec6"
"103c1bc8f418c3d89ef54f20c91e868043f50aa21335468692bf1c4c8ff263dd01907fdc4bc5f78c5f7e8116de053a12"
"a9e5e15dbb2784f23bdea59aff7c879ed9210e8b4ae5a623f97134ed160dd7d79a6f5c7940c0093881ad6cbdd50ba2";

static const uint8_t message[] = "GmSSL X509 RSA verification contract\n";

static int decode(const char *hex, uint8_t *out, size_t capacity, size_t *outlen)
{
	if (!hex || !out || !outlen) return -1;
	*outlen = 0;
	if (hex_to_bytes(hex, strlen(hex), out, outlen) != 1) return -1;
	return *outlen <= capacity ? 1 : -1;
}

int main(void)
{
	uint8_t spki[384];
	uint8_t spki_roundtrip[X509_PUBLIC_KEY_INFO_MAX_SIZE];
	uint8_t sig[RSA_MAX_MODULUS_SIZE];
	uint8_t cert[1024];
	uint8_t bad_cert[1024];
	size_t spki_len = 0;
	size_t spki_roundtrip_len = 0;
	size_t sig_len = 0;
	size_t cert_len = 0;
	const uint8_t *p;
	size_t plen;
	uint8_t *out;
	X509_KEY key;
	X509_KEY key2;
	X509_KEY cert_key;
	X509_SIGN_CTX verify_ctx;
	int sig_alg = OID_undef;

	if (decode(spki_hex, spki, sizeof(spki), &spki_len) != 1) return 1;
	if (decode(signature_hex, sig, sizeof(sig), &sig_len) != 1) return 2;
	if (decode(cert_hex, cert, sizeof(cert), &cert_len) != 1) return 3;

	p = spki;
	plen = spki_len;
	if (x509_public_key_info_from_der(&key, &p, &plen) != 1 || plen != 0) return 4;
	if (key.algor != OID_rsa_encryption || key.algor_param != OID_undef
		|| key.u.rsa_public_key.modulus_size != RSA_MIN_MODULUS_SIZE
		|| key.u.rsa_public_key.public_exponent != 65537u) return 5;

	out = spki_roundtrip;
	if (x509_public_key_info_to_der(&key, &out, &spki_roundtrip_len) != 1
		|| spki_roundtrip_len != spki_len
		|| memcmp(spki_roundtrip, spki, spki_len) != 0) return 6;

	p = spki_roundtrip;
	plen = spki_roundtrip_len;
	if (x509_public_key_info_from_der(&key2, &p, &plen) != 1 || plen != 0
		|| x509_public_key_equ(&key, &key2) != 1) return 7;

	if (x509_key_supports_sign_algor(&key, OID_rsasign_with_sha256) != 1) return 8;
	if (x509_verify_init_ex(&verify_ctx, &key, OID_rsasign_with_sha256,
			NULL, 0, sig, sig_len) != 1
		|| x509_verify_update(&verify_ctx, message, sizeof(message) - 1) != 1
		|| x509_verify_finish(&verify_ctx) != 1) return 9;
	x509_sign_ctx_cleanup(&verify_ctx);

	if (x509_cert_get_signature_algor(cert, cert_len, &sig_alg) != 1
		|| sig_alg != OID_rsasign_with_sha256) return 10;
	if (x509_cert_get_subject_public_key(cert, cert_len, &cert_key) != 1
		|| x509_public_key_equ(&key, &cert_key) != 1) return 11;
	if (x509_cert_is_signed_by_root_ca_cert(cert, cert_len, cert, cert_len, NULL, 0) != 1) return 12;

	memcpy(bad_cert, cert, cert_len);
	bad_cert[cert_len - 1] ^= 1u;
	if (x509_cert_is_signed_by_root_ca_cert(
			bad_cert, cert_len, cert, cert_len, NULL, 0) != 0) return 13;

	x509_key_cleanup(&cert_key);
	x509_key_cleanup(&key2);
	x509_key_cleanup(&key);
	puts("GmSSL X.509 RSA SHA-256 verification: PASS");
	return 0;
}
