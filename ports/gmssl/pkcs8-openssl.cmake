# Extend GmSSL PKCS#8 PBES2 parsing to the standard OpenSSL profile used
# by encrypted RSA identities: PBKDF2-HMAC-SHA256 + AES-256-CBC.
# Keep the existing HMAC-SM3 + SM4-CBC profile supported.

set(_gmssl_pkcs8_c "${SOURCE_PATH}/src/pkcs8.c")

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
char *pbkdf2_prf_name(int oid)
{
	switch (oid) {
	case OID_hmac_sm3: return "hmac-sm3";
	}
	return NULL;
}

int pbkdf2_prf_from_name(const char *name)
{
	if (strcmp(name, "hmac-sm3") == 0) {
		return OID_hmac_sm3;
	}
	return 0;
}
]==]
[==[
char *pbkdf2_prf_name(int oid)
{
	switch (oid) {
	case OID_hmac_sm3: return "hmac-sm3";
	case OID_hmac_sha256: return "hmac-sha256";
	}
	return NULL;
}

int pbkdf2_prf_from_name(const char *name)
{
	if (strcmp(name, "hmac-sm3") == 0) {
		return OID_hmac_sm3;
	}
	if (strcmp(name, "hmac-sha256") == 0) {
		return OID_hmac_sha256;
	}
	return 0;
}
]==]
)

gmssl_replace_once(
    "${_gmssl_pkcs8_c}"
[==[
int pbkdf2_prf_to_der(int oid, uint8_t **out, size_t *outlen)
{
	size_t len = 0;
	if (oid == -1)
		return 0;

	if (oid != OID_hmac_sm3) {
		error_print();
		return -1;
	}
	if (asn1_object_identifier_to_der(oid_hmac_sm3, oid_hmac_sm3_cnt, NULL, &len) != 1
		|| asn1_sequence_header_to_der(len, out, outlen) != 1
		|| asn1_object_identifier_to_der(oid_hmac_sm3, oid_hmac_sm3_cnt, out, outlen) != 1) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
[==[
int pbkdf2_prf_to_der(int oid, uint8_t **out, size_t *outlen)
{
	const uint32_t *nodes;
	size_t nodes_cnt;
	int encode_null = 0;
	size_t len = 0;

	if (oid == -1) return 0;
	switch (oid) {
	case OID_hmac_sm3:
		nodes = oid_hmac_sm3;
		nodes_cnt = oid_hmac_sm3_cnt;
		break;
	case OID_hmac_sha256:
		nodes = oid_hmac_sha256;
		nodes_cnt = oid_hmac_sha256_cnt;
		encode_null = 1;
		break;
	default:
		error_print();
		return -1;
	}
	if (asn1_object_identifier_to_der(nodes, nodes_cnt, NULL, &len) != 1
		|| (encode_null && asn1_null_to_der(NULL, &len) != 1)
		|| asn1_sequence_header_to_der(len, out, outlen) != 1
		|| asn1_object_identifier_to_der(nodes, nodes_cnt, out, outlen) != 1
		|| (encode_null && asn1_null_to_der(out, outlen) != 1)) {
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
	int null_param;

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
	} else if (asn1_object_identifier_equ(nodes, nodes_cnt, oid_hmac_sha256, oid_hmac_sha256_cnt) == 1) {
		*oid = OID_hmac_sha256;
	} else {
		error_print();
		return -1;
	}
	if ((null_param = asn1_null_from_der(&d, &dlen)) < 0
		|| asn1_length_is_zero(dlen) != 1) {
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
int pbes2_enc_algor_to_der(int oid, const uint8_t *iv, size_t ivlen, uint8_t **out, size_t *outlen)
{
	if (oid != OID_sm4_cbc) {
		error_print();
		return -1;
	}
	if (x509_encryption_algor_to_der(oid, iv, ivlen, out, outlen) != 1) {
]==]
[==[
int pbes2_enc_algor_to_der(int oid, const uint8_t *iv, size_t ivlen, uint8_t **out, size_t *outlen)
{
	if (oid != OID_sm4_cbc && oid != OID_aes256_cbc) {
		error_print();
		return -1;
	}
	if (x509_encryption_algor_to_der(oid, iv, ivlen, out, outlen) != 1) {
]==]
)

gmssl_replace_once(
    "${_gmssl_pkcs8_c}"
[==[
	if (*oid != OID_sm4_cbc) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
[==[
	if (*oid != OID_sm4_cbc && *oid != OID_aes256_cbc) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
)

unset(_gmssl_pkcs8_c)
