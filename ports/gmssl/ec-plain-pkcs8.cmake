# Unencrypted EC PKCS#8 PrivateKeyInfo loading required by Salts identities.
# Keep the existing password-bearing encrypted EC/SM2 path unchanged.

set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
]==]
[==[
static int x509_plain_ec_private_key_info_from_pem(X509_KEY *key, FILE *fp)
{
	enum { X509_PLAIN_EC_PKCS8_MAX_DER_SIZE = 4096 };
	uint8_t buf[X509_PLAIN_EC_PKCS8_MAX_DER_SIZE];
	const uint8_t *p = buf;
	size_t len = 0;
	const uint8_t *attrs = NULL;
	size_t attrslen = 0;
	int ret = -1;

	memset(buf, 0, sizeof(buf));
	if (!key || !fp) {
		error_print();
		return -1;
	}
	if (pem_read(fp, "PRIVATE KEY", buf, &len, sizeof(buf)) != 1
		|| x509_private_key_info_from_der(key, &attrs, &attrslen, &p, &len) != 1
		|| asn1_length_is_zero(len) != 1
		|| attrslen != 0
		|| key->algor != OID_ec_public_key
		|| key->algor_param != OID_secp256r1) {
		error_print();
		goto end;
	}
	ret = 1;

end:
	gmssl_secure_clear(buf, sizeof(buf));
	if (ret != 1) {
		x509_key_cleanup(key);
	}
	return ret;
}

int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (algor == OID_ec_public_key) {
		int ret;
		const uint8_t *attrs;
		size_t attrslen;
		if (!pass) {
			error_print();
			return -1;
		}
		if ((ret = x509_private_key_info_decrypt_from_pem(key, &attrs, &attrslen, pass, fp)) < 0) {
			error_print();
			return -1;
		} else if (ret == 0) {
			return 0; // TODO: support return 0 for other algors
		}
	}
]==]
[==[
	if (algor == OID_ec_public_key) {
		int ret;
		const uint8_t *attrs;
		size_t attrslen;
		if (pass && pass[0]) {
			if ((ret = x509_private_key_info_decrypt_from_pem(
					key, &attrs, &attrslen, pass, fp)) < 0) {
				error_print();
				return -1;
			} else if (ret == 0) {
				return 0;
			}
		} else {
			if (x509_plain_ec_private_key_info_from_pem(key, fp) != 1) {
				error_print();
				return -1;
			}
		}
	}
]==]
)

unset(_gmssl_x509_c)
