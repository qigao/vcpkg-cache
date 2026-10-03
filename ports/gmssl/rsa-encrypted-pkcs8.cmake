# Password-protected RSA PKCS#8 loading for both the GmSSL native PBES2
# profile and the common OpenSSL PBKDF2-HMAC-SHA256 + AES-256-CBC profile.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_private_key_info_from_pem(RSA_PRIVATE_KEY *key, FILE *fp);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
[==[
int rsa_private_key_info_from_pem(RSA_PRIVATE_KEY *key, FILE *fp);
int rsa_private_key_info_decrypt_from_der(RSA_PRIVATE_KEY *key,
	const uint8_t **attrs, size_t *attrslen, const char *pass,
	const uint8_t **in, size_t *inlen);
int rsa_private_key_info_decrypt_from_pem(RSA_PRIVATE_KEY *key,
	const char *pass, FILE *fp);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
#include <gmssl/asn1.h>
#include <gmssl/pem.h>
#include <gmssl/x509_alg.h>
]==]
[==[
#include <gmssl/asn1.h>
#include <gmssl/pem.h>
#include <gmssl/pkcs8.h>
#include <gmssl/pbkdf2.h>
#include <gmssl/digest.h>
#include <gmssl/aes.h>
#include <gmssl/sm4.h>
#include <gmssl/x509_alg.h>
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key)
{
	if (key) {
		gmssl_secure_clear(key, sizeof(*key));
	}
}
]==]
[==[
int rsa_private_key_info_decrypt_from_der(RSA_PRIVATE_KEY *key,
	const uint8_t **attrs, size_t *attrslen, const char *pass,
	const uint8_t **in, size_t *inlen)
{
	enum { RSA_PKCS8_MAX_DER_SIZE = 4096 };
	const uint8_t *salt;
	size_t saltlen;
	int iter;
	int keylen;
	int prf;
	int cipher;
	const uint8_t *iv;
	size_t ivlen;
	const uint8_t *enced;
	size_t encedlen;
	const DIGEST *digest = NULL;
	uint8_t derived_key[AES256_KEY_SIZE];
	size_t derived_key_len = 0;
	uint8_t plain[RSA_PKCS8_MAX_DER_SIZE];
	size_t plainlen = 0;
	const uint8_t *p;
	AES_KEY aes_key;
	SM4_KEY sm4_key;
	int ret = -1;

	if (attrs) *attrs = NULL;
	if (attrslen) *attrslen = 0;
	memset(derived_key, 0, sizeof(derived_key));
	memset(plain, 0, sizeof(plain));
	memset(&aes_key, 0, sizeof(aes_key));
	memset(&sm4_key, 0, sizeof(sm4_key));

	if (!key || !pass || !in || !*in || !inlen) {
		error_print();
		goto end;
	}
	if (pkcs8_enced_private_key_info_from_der(
			&salt, &saltlen, &iter, &keylen, &prf,
			&cipher, &iv, &ivlen, &enced, &encedlen,
			in, inlen) != 1
		|| !salt || !saltlen || saltlen > PBKDF2_MAX_SALT_SIZE
		|| iter <= 0 || !iv || ivlen != AES_BLOCK_SIZE
		|| !enced || !encedlen || encedlen > sizeof(plain)
		|| (encedlen % AES_BLOCK_SIZE) != 0) {
		error_print();
		goto end;
	}

	if (cipher == OID_aes256_cbc) {
		if (prf != OID_hmac_sha256 || (keylen != -1 && keylen != AES256_KEY_SIZE)) {
			error_print();
			goto end;
		}
		digest = DIGEST_sha256();
		derived_key_len = AES256_KEY_SIZE;
	} else if (cipher == OID_sm4_cbc) {
		if ((prf != -1 && prf != OID_hmac_sm3) || (keylen != -1 && keylen != SM4_KEY_SIZE)) {
			error_print();
			goto end;
		}
		digest = DIGEST_sm3();
		derived_key_len = SM4_KEY_SIZE;
	} else {
		error_print();
		goto end;
	}
	if (!digest
		|| pbkdf2_hmac_genkey(digest, pass, strlen(pass),
			salt, saltlen, (size_t)iter,
			derived_key_len, derived_key) != 1) {
		error_print();
		goto end;
	}

	if (cipher == OID_aes256_cbc) {
		if (aes_set_decrypt_key(&aes_key, derived_key, derived_key_len) != 1
			|| aes_cbc_padding_decrypt(&aes_key, iv,
				enced, encedlen, plain, &plainlen) != 1) {
			error_print();
			goto end;
		}
	} else {
		sm4_set_decrypt_key(&sm4_key, derived_key);
		if (sm4_cbc_padding_decrypt(&sm4_key, iv,
				enced, encedlen, plain, &plainlen) != 1) {
			error_print();
			goto end;
		}
	}
	p = plain;
	if (rsa_private_key_info_from_der(key, attrs, attrslen, &p, &plainlen) != 1
		|| asn1_length_is_zero(plainlen) != 1) {
		error_print();
		goto end;
	}
	ret = 1;

end:
	if (ret != 1 && key) {
		rsa_private_key_cleanup(key);
	}
	gmssl_secure_clear(derived_key, sizeof(derived_key));
	gmssl_secure_clear(plain, sizeof(plain));
	gmssl_secure_clear(&aes_key, sizeof(aes_key));
	gmssl_secure_clear(&sm4_key, sizeof(sm4_key));
	return ret;
}

int rsa_private_key_info_decrypt_from_pem(RSA_PRIVATE_KEY *key,
	const char *pass, FILE *fp)
{
	enum { RSA_ENCRYPTED_PKCS8_MAX_DER_SIZE = 4608 };
	uint8_t buf[RSA_ENCRYPTED_PKCS8_MAX_DER_SIZE];
	const uint8_t *p = buf;
	size_t len = 0;
	const uint8_t *attrs = NULL;
	size_t attrslen = 0;
	int pem_ret;
	int ret = -1;

	if (!key || !pass || !fp) {
		error_print();
		return -1;
	}
	memset(buf, 0, sizeof(buf));
	pem_ret = pem_read(fp, "ENCRYPTED PRIVATE KEY", buf, &len, sizeof(buf));
	if (pem_ret < 0) {
		error_print();
		goto end;
	}
	if (pem_ret == 0) {
		ret = 0;
		goto end;
	}
	if (rsa_private_key_info_decrypt_from_der(
			key, &attrs, &attrslen, pass, &p, &len) != 1
		|| asn1_length_is_zero(len) != 1
		|| attrslen != 0) {
		error_print();
		goto end;
	}
	ret = 1;

end:
	gmssl_secure_clear(buf, sizeof(buf));
	if (ret != 1) {
		rsa_private_key_cleanup(key);
	}
	return ret;
}

void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key)
{
	if (key) {
		gmssl_secure_clear(key, sizeof(*key));
	}
}
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
