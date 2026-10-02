# Unencrypted RSA PKCS#8 PrivateKeyInfo loading for Salts TLS identities.
# This layer converts PRIVATE KEY PEM/DER into the bounded RSA_PRIVATE_KEY.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
[==[
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
int rsa_private_key_info_from_der(RSA_PRIVATE_KEY *key,
	const uint8_t **attrs, size_t *attrslen,
	const uint8_t **in, size_t *inlen);
int rsa_private_key_info_from_pem(RSA_PRIVATE_KEY *key, FILE *fp);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
#include <gmssl/sha2.h>
#include <gmssl/asn1.h>
#include <gmssl/error.h>
]==]
[==[
#include <gmssl/sha2.h>
#include <gmssl/asn1.h>
#include <gmssl/pem.h>
#include <gmssl/x509_alg.h>
#include <gmssl/error.h>
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
int rsa_private_key_info_from_der(RSA_PRIVATE_KEY *key,
	const uint8_t **attrs, size_t *attrslen,
	const uint8_t **in, size_t *inlen)
{
	const uint8_t *d;
	size_t dlen;
	int version;
	int algor;
	int algor_param;
	const uint8_t *private_key;
	size_t private_key_len;
	const uint8_t *local_attrs = NULL;
	size_t local_attrs_len = 0;
	const uint8_t *p;
	size_t len;

	if (attrs) *attrs = NULL;
	if (attrslen) *attrslen = 0;
	if (!key || !in || !*in || !inlen) {
		error_print();
		return -1;
	}
	if (asn1_sequence_from_der(&d, &dlen, in, inlen) != 1
		|| asn1_int_from_der(&version, &d, &dlen) != 1
		|| x509_public_key_algor_from_der(&algor, &algor_param, &d, &dlen) != 1
		|| asn1_octet_string_from_der(&private_key, &private_key_len, &d, &dlen) != 1
		|| asn1_implicit_set_from_der(0, &local_attrs, &local_attrs_len, &d, &dlen) < 0
		|| asn1_length_is_zero(dlen) != 1) {
		error_print();
		return -1;
	}
	if (version != 0 || algor != OID_rsa_encryption || algor_param != OID_undef
		|| !private_key || !private_key_len) {
		error_print();
		return -1;
	}
	p = private_key;
	len = private_key_len;
	if (rsa_private_key_from_der(key, &p, &len) != 1
		|| asn1_length_is_zero(len) != 1) {
		error_print();
		return -1;
	}
	if (attrs) *attrs = local_attrs;
	if (attrslen) *attrslen = local_attrs_len;
	return 1;
}

int rsa_private_key_info_from_pem(RSA_PRIVATE_KEY *key, FILE *fp)
{
	enum { RSA_PKCS8_MAX_DER_SIZE = 4096 };
	uint8_t buf[RSA_PKCS8_MAX_DER_SIZE];
	const uint8_t *p = buf;
	size_t len = 0;
	const uint8_t *attrs = NULL;
	size_t attrslen = 0;
	int ret = -1;

	if (!key || !fp) {
		error_print();
		return -1;
	}
	if (pem_read(fp, "PRIVATE KEY", buf, &len, sizeof(buf)) != 1
		|| rsa_private_key_info_from_der(key, &attrs, &attrslen, &p, &len) != 1
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
