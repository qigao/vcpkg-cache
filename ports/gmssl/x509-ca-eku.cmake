# RFC 5280 extended-key-usage constraints on certification authorities.

set(_gmssl_x509_ext_c "${SOURCE_PATH}/src/x509_ext.c")
set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_cer.c")

# x509_exts_check() validates a certificate's structural role. An EKU on a CA
# constrains paths issued by that CA; it is not itself a leaf-certificate use.
# Parse the extension here and defer the requested-purpose check to chain
# validation, which knows whether the path is for server or client auth.
gmssl_replace_once(
    "${_gmssl_x509_ext_c}"
[==[
		case OID_ce_ext_key_usage:
			if (x509_ext_key_usage_from_der(ext_key_usages, &ext_key_usages_cnt,
					sizeof(ext_key_usages)/sizeof(ext_key_usages[0]), &val, &vlen) != 1
				|| x509_ext_key_usage_check(ext_key_usages, ext_key_usages_cnt, cert_type) != 1) {
				error_print();
				return -1;
			}
			break;
]==]
[==[
		case OID_ce_ext_key_usage:
			if (x509_ext_key_usage_from_der(ext_key_usages, &ext_key_usages_cnt,
					sizeof(ext_key_usages)/sizeof(ext_key_usages[0]), &val, &vlen) != 1) {
				error_print();
				return -1;
			}
			if (!is_ca
				&& x509_ext_key_usage_check(ext_key_usages, ext_key_usages_cnt, cert_type) != 1) {
				error_print();
				return -1;
			}
			break;
]==]
)

# Validate an intermediate/root CA's EKU against the purpose of the path. A CA
# without EKU is unrestricted; anyExtendedKeyUsage or the requested purpose is
# accepted. A serverAuth-only CA therefore cannot validate a client-auth path.
gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
static void x509_verify_set_result(int *verify_result, int result)
{
	if (verify_result) {
		*verify_result = result;
	}
}
]==]
[==[
static void x509_verify_set_result(int *verify_result, int result)
{
	if (verify_result) {
		*verify_result = result;
	}
}

static int x509_cert_check_ca_key_purpose(const uint8_t *cert, size_t certlen,
	int entity_cert_type)
{
	const uint8_t *exts;
	size_t extslen;
	const uint8_t *val;
	size_t vlen;
	int critical;
	int key_purposes[X509_MAX_KEY_PURPOSES];
	size_t key_purposes_cnt;
	size_t i;
	int ret;

	if (x509_cert_get_exts(cert, certlen, &exts, &extslen) != 1) {
		error_print();
		return -1;
	}
	ret = x509_exts_get_ext_by_oid(exts, extslen, OID_ce_ext_key_usage,
		&critical, &val, &vlen);
	if (ret < 0) {
		error_print();
		return -1;
	}
	if (ret == 0) {
		return 1;
	}
	if (x509_ext_key_usage_from_der(key_purposes, &key_purposes_cnt,
			sizeof(key_purposes)/sizeof(key_purposes[0]), &val, &vlen) != 1
		|| vlen != 0) {
		error_print();
		return -1;
	}
	for (i = 0; i < key_purposes_cnt; i++) {
		if (key_purposes[i] == OID_any_extended_key_usage) {
			return 1;
		}
	}
	return x509_ext_key_usage_check(
		key_purposes, key_purposes_cnt, entity_cert_type) == 1 ? 1 : 0;
}

static int x509_cert_check_ca_for_purpose(const uint8_t *cert, size_t certlen,
	int entity_cert_type)
{
	if (x509_cert_check(cert, certlen, X509_cert_ca) != 1
		|| x509_cert_check_ca_key_purpose(cert, certlen, entity_cert_type) != 1) {
		error_print();
		return -1;
	}
	return 1;
}
]==]
)

# Standard TLS chain: enforce the entity purpose for every CA and trust anchor.
foreach(_gmssl_x509_standard_ca_check RANGE 1 2)
    gmssl_replace_once(
        "${_gmssl_x509_c}"
        "x509_cert_check(cacert, cacertlen, X509_cert_ca)"
        "x509_cert_check_ca_for_purpose(cacert, cacertlen, entity_cert_type)"
    )
endforeach()

# TLCP chain: the signing certificate determines the authentication purpose.
foreach(_gmssl_x509_tlcp_ca_check RANGE 1 2)
    gmssl_replace_once(
        "${_gmssl_x509_c}"
        "x509_cert_check(cacert, cacertlen, X509_cert_ca)"
        "x509_cert_check_ca_for_purpose(cacert, cacertlen, sign_cert_type)"
    )
endforeach()

file(READ "${_gmssl_x509_ext_c}" _gmssl_x509_ca_eku_ext_after)
file(READ "${_gmssl_x509_c}" _gmssl_x509_ca_eku_cer_after)
foreach(_needle
    "if (!is_ca"
    "static int x509_cert_check_ca_key_purpose"
    "x509_cert_check_ca_for_purpose(cacert, cacertlen, entity_cert_type)"
    "x509_cert_check_ca_for_purpose(cacert, cacertlen, sign_cert_type)")
    string(FIND "${_gmssl_x509_ca_eku_ext_after}${_gmssl_x509_ca_eku_cer_after}"
        "${_needle}" _offset)
    if(_offset EQUAL -1)
        message(FATAL_ERROR "GmSSL CA EKU path constraint missing: ${_needle}")
    endif()
endforeach()

unset(_offset)
unset(_needle)
unset(_gmssl_x509_ca_eku_cer_after)
unset(_gmssl_x509_ca_eku_ext_after)
unset(_gmssl_x509_tlcp_ca_check)
unset(_gmssl_x509_standard_ca_check)
unset(_gmssl_x509_c)
unset(_gmssl_x509_ext_c)
