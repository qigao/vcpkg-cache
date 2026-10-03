# OpenSSL-compatible encrypted RSA PKCS#8 support required by Salts key_password.
# Preserve the existing SM4/HMAC-SM3 generic PKCS#8 behavior while adding the
# bounded PBES2/PBKDF2/HMAC-SHA256/AES-256-CBC decode path used by ordinary
# OpenSSL "ENCRYPTED PRIVATE KEY" identities.

set(_gmssl_pkcs8_c "${SOURCE_PATH}/src/pkcs8.c")
set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_pkcs8_c}"
[==[
static const uint32_t oid_hmac_sm3[] = { oid_sm_algors,401,2 };
static const size_t oid_hmac_sm3_cnt = sizeof(oid_hmac_sm3)/sizeof(oid_hmac_sm3[0]);
]==]
[==[
static const uint32_t oid_hmac_sm3[] = { oid_sm_algors,401,2 };
static const size_t oid_hmac_sm3_cnt = sizeof(oid_hmac_sm3)/sizeof(oid_hmac_sm3[0]);
static const uint32_t oid_hmac_sha256[] = { 1,2,840,113549,2,9 };
static const size_t oid_hmac_sha256_cnt = sizeof(oid_hmac_sha256)/sizeof(oid_hmac_sha256[0]);
]==]
)

gmssl_replace_once(
    "${_gmssl_pkcs8_c}"
[==[
int pbkdf2_prf_from_der(int *oid, const uint8_t **in, size_t *inlen)
{
	int ret;
	const uint8_t *d;
	size_t dlen;
	uint32_t nodes[32];
	size_t nodes_cnt;

	if ((ret = asn1_sequence_from_der(&d, &dlen, in, inlen)) != 1) {
		if (ret < 0) error_print();
		else *oid = -1;
		return ret;
	}
	if (asn1_object_identifier_from_der(nodes, &nodes_cnt, &d, &dlen) != 1
		|| asn1_object_identifier_equ(nodes, nodes_cnt, oid_hmac_sm3, oid_hmac_sm3_cnt) != 1
		|| asn1_length_is_zero(dlen) != 1) {
		error_print();
		return -1;
	}
	*oid = OID_hmac_sm3;
	return 1;
}
]==]
[==[
int pbkdf2_prf_from_der(int *oid, const uint8_t **in, size_t *inlen)
{
	int ret;
	const uint8_t *d;
	size_t dlen;
	uint32_t nodes[32];
	size_t nodes_cnt;

	if ((ret = asn1_sequence_from_der(&d, &dlen, in, inlen)) != 1) {
		if (ret < 0) error_print();
		else *oid = -1;
		return ret;
	}
	if (asn1_object_identifier_from_der(nodes, &nodes_cnt, &d, &dlen) != 1) {
		error_print();
		return -1;
	}
	if (asn1_object_identifier_equ(nodes, nodes_cnt, oid_hmac_sm3, oid_hmac_sm3_cnt) == 1) {
		*oid = OID_hmac_sm3;
	} else if (asn1_object_identifier_equ(nodes, nodes_cnt,
			oid_hmac_sha256, oid_hmac_sha256_cnt) == 1) {
		*oid = OID_hmac_sha256;
	} else {
		error_print();
		return -1;
	}
	/* OpenSSL emits AlgorithmIdentifier parameters as NULL; GmSSL's SM3
	 * writer omits them. Accept both canonical encodings. */
	if (dlen && asn1_null_from_der(&d, &dlen) != 1) {
		error_print();
		return -1;
	}
	if (asn1_length_is_zero(dlen) != 1) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
)

gmssl_replace_once(
    "${_gmssl_pkcs8_c}"
[==[
	if (*oid != OID_sm4_cbc) {
		error_print();
		return -1;
	}
]==]
[==[
	if (*oid != OID_sm4_cbc && *oid != OID_aes256_cbc) {
		error_print();
		return -1;
	}
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
#include <gmssl/sm4.h>
#include <gmssl/rsa.h>
]==]
[==[
#include <gmssl/sm4.h>
#include <gmssl/aes.h>
#include <gmssl/pbkdf2.h>
#include <gmssl/rsa.h>
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
]==]
[==[
static int x509_rsa_private_key_from_encrypted_pem(
	RSA_PRIVATE_KEY *private_key, const char *pass, FILE *fp)
{
	enum { RSA_ENCRYPTED_PKCS8_MAX_DER_SIZE = 8192 };
	uint8_t encoded[RSA_ENCRYPTED_PKCS8_MAX_DER_SIZE];
	uint8_t plaintext[RSA_ENCRYPTED_PKCS8_MAX_DER_SIZE];
	uint8_t raw_key[AES256_KEY_SIZE];
	AES_KEY aes_key;
	const uint8_t *p = encoded;
	size_t encoded_len = 0;
	const uint8_t *salt = NULL;
	size_t saltlen = 0;
	int iter = 0;
	int keylen = 0;
	int prf = OID_undef;
	int cipher = OID_undef;
	const uint8_t *iv = NULL;
	size_t ivlen = 0;
	const uint8_t *encrypted = NULL;
	size_t encrypted_len = 0;
	size_t plaintext_len = 0;
	const uint8_t *attrs = NULL;
	size_t attrslen = 0;
	int ret = -1;

	memset(encoded, 0, sizeof(encoded));
	memset(plaintext, 0, sizeof(plaintext));
	memset(raw_key, 0, sizeof(raw_key));
	memset(&aes_key, 0, sizeof(aes_key));
	memset(private_key, 0, sizeof(*private_key));

	if (!pass || !pass[0] || !fp) {
		error_print();
		goto end;
	}
	if (pem_read(fp, "ENCRYPTED PRIVATE KEY",
			encoded, &encoded_len, sizeof(encoded)) != 1) {
		error_print();
		goto end;
	}
	if (pkcs8_enced_private_key_info_from_der(
			&salt, &saltlen, &iter, &keylen, &prf,
			&cipher, &iv, &ivlen, &encrypted, &encrypted_len,
			&p, &encoded_len) != 1
		|| asn1_length_is_zero(encoded_len) != 1
		|| !salt || saltlen == 0 || saltlen > PBKDF2_MAX_SALT_SIZE
		|| iter <= 0
		|| (keylen != -1 && keylen != AES256_KEY_SIZE)
		|| prf != OID_hmac_sha256
		|| cipher != OID_aes256_cbc
		|| !iv || ivlen != AES_BLOCK_SIZE
		|| !encrypted || encrypted_len == 0
		|| encrypted_len > sizeof(plaintext)) {
		error_print();
		goto end;
	}
	if (pbkdf2_hmac_genkey(DIGEST_sha256(),
			pass, strlen(pass), salt, saltlen, (size_t)iter,
			sizeof(raw_key), raw_key) != 1
		|| aes_set_decrypt_key(&aes_key, raw_key, sizeof(raw_key)) != 1
		|| aes_cbc_padding_decrypt(&aes_key, iv,
			encrypted, encrypted_len, plaintext, &plaintext_len) != 1) {
		error_print();
		goto end;
	}
	p = plaintext;
	if (rsa_private_key_info_from_der(private_key,
			&attrs, &attrslen, &p, &plaintext_len) != 1
		|| asn1_length_is_zero(plaintext_len) != 1
		|| attrslen != 0) {
		error_print();
		goto end;
	}
	ret = 1;

end:
	gmssl_secure_clear(&aes_key, sizeof(aes_key));
	gmssl_secure_clear(raw_key, sizeof(raw_key));
	gmssl_secure_clear(plaintext, sizeof(plaintext));
	gmssl_secure_clear(encoded, sizeof(encoded));
	if (ret != 1) rsa_private_key_cleanup(private_key);
	return ret;
}

int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (algor == OID_rsa_encryption) {
		RSA_PRIVATE_KEY private_key;
		memset(&private_key, 0, sizeof(private_key));
		if (rsa_private_key_info_from_pem(&private_key, fp) != 1) {
			rsa_private_key_cleanup(&private_key);
			error_print();
			return -1;
		}
]==]
[==[
	if (algor == OID_rsa_encryption) {
		RSA_PRIVATE_KEY private_key;
		int load_ret;
		memset(&private_key, 0, sizeof(private_key));
		load_ret = pass && pass[0]
			? x509_rsa_private_key_from_encrypted_pem(&private_key, pass, fp)
			: rsa_private_key_info_from_pem(&private_key, fp);
		if (load_ret != 1) {
			rsa_private_key_cleanup(&private_key);
			error_print();
			return -1;
		}
]==]
)

unset(_gmssl_pkcs8_c)
unset(_gmssl_x509_c)
