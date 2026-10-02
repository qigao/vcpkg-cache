#include <gmssl/tls.h>
#include <gmssl/x509_key.h>

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
		"cb90dfee5485fce4a19102b75eba4905547a62e5329c63d314f0f65002ffe0a"
		"6bc901aa460566b9cc8435a9a3704cd65fb6459391943ef5ce802cbe5e7f028"
		"d6a3fc4ac8f2796e7d2c94b730753c718eb682dde7b6a5daf877bcf7595fcbd8"
		"0e2dc7fd44ec711c28c68db56717e75496a7c9d565be8783acbb959fbc0abdc2"
		"87168909ca2a28c4a73c4cdd7ac29c5fc43befc85eeb881af0040d07979d2042"
		"608cfa02c3f52911f9225a78c151fcf0f5679a2cc8bbb6f129b6104dbf258181"
		"80657ad8a1d3fc85c9de952ccaec4ade6dff355af1a3aebd9088adf666b28fcd"
		"74f2b98502eef9611be67a03970c8e7743cb6367b41c4435a6c963cbf6039f96"
		"6f0203010001";
	static const char signature_hex[] =
		"3171acc742178e3a0b09c85a4da5aad0475135f3473088d8071a38b458f9d7a8"
		"b743bce22f24f476da2b11f11b0a9eeea7c985aed75badf7b81d53811b46f748"
		"7aa527efca1207b589d0132617a704830efeda37a49d406ea5034aa5b13f91e3"
		"3bf687b70e10b29fe5f50bff0fd1176cf023ba6c68606d15d37ccd486f0a479a"
		"09a6db37a795966f993d7299c472ab98bd6afba7a9ebd750a8df0e91bbe6f49c"
		"b9c70b7b9dbc5695252d058aabb9efe3226073201690e1d11f51245cc77d4a61"
		"be79d2523367568bb182117b90143323e79a71ff5c7a100f00fd589263a0446f"
		"91f3c799ad0b1f51ab5827eae492beb4cd66dce6347741ddbcbed182352ebf7f";
	static const char cert_hex[] =
		"308202d4308201bca003020102020101300d06092a864886f70d01010b05003023"
		"3121301f06035504030c18676d73736c2d746c7331332d7273612d636f6e747261"
		"6374301e170d3236303130313030303030305a170d333530313031303030303030"
		"5a30233121301f06035504030c18676d73736c2d746c7331332d7273612d636f6e"
		"747261637430820122300d06092a864886f70d01010105000382010f003082010a"
		"0282010100cb90dfee5485fce4a19102b75eba4905547a62e5329c63d314f0f65"
		"002ffe0a6bc901aa460566b9cc8435a9a3704cd65fb6459391943ef5ce802cbe5"
		"e7f028d6a3fc4ac8f2796e7d2c94b730753c718eb682dde7b6a5daf877bcf759"
		"5fcbd80e2dc7fd44ec711c28c68db56717e75496a7c9d565be8783acbb959fbc"
		"0abdc287168909ca2a28c4a73c4cdd7ac29c5fc43befc85eeb881af0040d0797"
		"9d2042608cfa02c3f52911f9225a78c151fcf0f5679a2cc8bbb6f129b6104dbf"
		"25818180657ad8a1d3fc85c9de952ccaec4ade6dff355af1a3aebd9088adf666"
		"b28fcd74f2b98502eef9611be67a03970c8e7743cb6367b41c4435a6c963cbf6"
		"039f966f0203010001a3133011300f0603551d130101ff040530030101ff300d06"
		"092a864886f70d01010b05000382010100c9eee564ddbcdc86c454af9194266bd7"
		"21c67e0bb898ad6368ff202fc5422afca33a5dd0809c0518676038e93ae8a2108"
		"f76a688723bf94d22ecba2b60a8f8dec7c52485bd32e1336bdfc4413372364b6"
		"e2793ca2ff7e3da141823b5e4cb8c49ecc83cd0f5655113d5f50b1b3b132330a4"
		"bea051ef9de58f99b00e643b448336fa49ed8402793d42a5890ee835c013a322d3"
		"e2e5f6b331fe93aeca4eba7ad07adbed29927d5f9d9b56bc3cf184b6b182ae44f"
		"c52aee27578aa90283632061f80912b6c663ee7a67edf5f13004e50ad14d114ab"
		"87457dfc4da3fc69535d836a5ddd51d7d9f340bd89c11804a59d1b702e644b4f"
		"d5306e0953c2b99e26629ec78e";
	static const uint8_t transcript[] =
		"GmSSL TLS 1.3 RSA-PSS CertificateVerify contract transcript";
	uint8_t spki[320];
	uint8_t sig[RSA_MAX_MODULUS_SIZE];
	uint8_t cert[800];
	size_t spki_len = 0;
	size_t sig_len = 0;
	size_t cert_len = 0;
	const uint8_t *p;
	size_t len;
	X509_KEY key;
	TLS_CTX tls_ctx;
	DIGEST_CTX transcript_ctx;
	const int offered[] = {
		TLS_sig_ecdsa_secp256r1_sha256,
		TLS_sig_rsa_pss_rsae_sha256,
	};
	int selected = 0;
	int ret;

	if (sizeof(TLS_CTX) != tls_ctx_sizeof()
		|| sizeof(TLS_CONNECT) != tls_connect_sizeof()) return 1;
	if (hex_to_bytes(spki_hex, spki, sizeof(spki), &spki_len) != 1) return 2;
	if (hex_to_bytes(signature_hex, sig, sizeof(sig), &sig_len) != 1) return 3;
	if (hex_to_bytes(cert_hex, cert, sizeof(cert), &cert_len) != 1) return 4;

	p = spki;
	len = spki_len;
	if (x509_public_key_info_from_der(&key, &p, &len) != 1 || len != 0) return 5;
	if (key.algor != OID_rsa_encryption
		|| key.u.rsa_public_key.modulus_size != sig_len) return 6;

	{
		const int pss_sig_alg = TLS_sig_rsa_pss_rsae_sha256;
		if (tls_ctx_init(&tls_ctx, TLS_protocol_tls13, TLS_client_mode) != 1) return 7;
		if (tls_ctx_set_signature_algorithms(&tls_ctx, &pss_sig_alg, 1) != 1) return 16;
		tls_ctx_cleanup(&tls_ctx);
	}
	if (tls_signature_scheme_from_algorithm_and_group_oid(
			OID_rsasign_with_sha256, OID_undef) != TLS_sig_rsa_pkcs1_sha256) return 8;
	if (tls_signature_scheme_algorithm_oid(
			TLS_sig_rsa_pkcs1_sha256) != OID_rsasign_with_sha256) return 9;
	if (tls_signature_scheme_group_oid(
			TLS_sig_rsa_pss_rsae_sha256) != OID_undef) return 10;

	if (tls_cert_match_signature_algorithms(cert, cert_len,
			offered, sizeof(offered)/sizeof(offered[0]), &selected) != 1
		|| selected != TLS_sig_rsa_pss_rsae_sha256) return 11;

	if (digest_init(&transcript_ctx, DIGEST_sha256()) != 1
		|| digest_update(&transcript_ctx, transcript, sizeof(transcript) - 1) != 1) return 12;
	ret = tls13_verify_certificate_verify(TLS_server_mode,
		TLS_sig_rsa_pss_rsae_sha256, &key, &transcript_ctx, sig, sig_len);
	if (ret != 1) return 13;

	sig[sig_len - 1] ^= 0x01u;
	if (digest_init(&transcript_ctx, DIGEST_sha256()) != 1
		|| digest_update(&transcript_ctx, transcript, sizeof(transcript) - 1) != 1) return 14;
	ret = tls13_verify_certificate_verify(TLS_server_mode,
		TLS_sig_rsa_pss_rsae_sha256, &key, &transcript_ctx, sig, sig_len);
	if (ret == 1) return 15;

	x509_key_cleanup(&key);
	puts("GmSSL TLS 1.3 RSA-PSS verification contract: PASS");
	return 0;
}
