# Route RSA X509 identity loading through encrypted PKCS#8 when a password
# is explicitly supplied, while preserving the existing unencrypted path.

set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")

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
		memset(key, 0, sizeof(*key));
		key->algor = OID_rsa_encryption;
		key->algor_param = OID_undef;
		key->u.rsa_public_key = private_key.public_key;
		key->rsa_private_key = private_key;
		key->has_private_key = 1;
		gmssl_secure_clear(&private_key, sizeof(private_key));
		return 1;
	}
]==]
[==[
	if (algor == OID_rsa_encryption) {
		RSA_PRIVATE_KEY private_key;
		int ret;
		memset(&private_key, 0, sizeof(private_key));
		if (pass && pass[0]) {
			ret = rsa_private_key_info_decrypt_from_pem(&private_key, pass, fp);
		} else {
			ret = rsa_private_key_info_from_pem(&private_key, fp);
		}
		if (ret != 1) {
			rsa_private_key_cleanup(&private_key);
			error_print();
			return -1;
		}
		memset(key, 0, sizeof(*key));
		key->algor = OID_rsa_encryption;
		key->algor_param = OID_undef;
		key->u.rsa_public_key = private_key.public_key;
		key->rsa_private_key = private_key;
		key->has_private_key = 1;
		gmssl_secure_clear(&private_key, sizeof(private_key));
		return 1;
	}
]==]
)

unset(_gmssl_x509_c)
