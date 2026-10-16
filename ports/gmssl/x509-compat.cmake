# X.509 interoperability fixes required by standard TLS peers.

set(_gmssl_x509_ext_c "${SOURCE_PATH}/src/x509_ext.c")

# RFC 5280 BasicConstraints has cA BOOLEAN DEFAULT FALSE and optional
# pathLenConstraint. Therefore an empty SEQUENCE is the canonical encoding of
# an end-entity CA:FALSE constraint. GmSSL 3.2.0 incorrectly rejects it.
gmssl_replace_once(
    "${_gmssl_x509_ext_c}"
[==[
	if (dlen == 0) {
		error_print();
		return -1;
	}
	if (asn1_boolean_from_der(ca, &d, &dlen) < 0
]==]
[==[
	if (dlen == 0) {
		*ca = 0;
		*path_len_cons = -1;
		return 1;
	}
	if (asn1_boolean_from_der(ca, &d, &dlen) < 0
]==]
)

unset(_gmssl_x509_ext_c)

set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_cer.c")

# RFC 5280 requires the current time to be inside a certificate's validity
# interval, but does not impose GmSSL's local ten-year duration limit. Public
# trust anchors such as ISRG Root X1 legitimately exceed that duration. Keep
# x509_validity_check()'s explicit policy mode for callers that request it and
# let certificate validation opt out with max_secs < 0.
gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (!(not_after - not_before <= (unsigned int)max_secs)) {
		error_print();
		return -1;
	}
]==]
[==[
	if (max_secs >= 0 && (uint64_t)(not_after - not_before) > (uint64_t)max_secs) {
		error_print();
		return -1;
	}
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
    "x509_validity_check(not_before, not_after, now, X509_VALIDITY_MAX_SECONDS)"
    "x509_validity_check(not_before, not_after, now, -1)"
)

# RFC 5280 serial numbers are positive integers up to 20 octets. There is no
# minimum four-byte requirement; MySQL's generated CA legitimately uses 0x01.
gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (serial_len < 4) {
		error_print(); // not enough randomness
		return -1; // FIXME: 通过宏设置错误？还是返回一个错误原因，让应用判断？
	}
]==]
[==[
	/* RFC 5280 does not impose a minimum serial-number width. The existing
	 * non-empty check above is sufficient for interoperable certificate parsing. */
]==]
)

file(READ "${_gmssl_x509_c}" _gmssl_x509_after)
string(FIND "${_gmssl_x509_after}" "if (serial_len < 4)" _gmssl_x509_short_serial_guard)
if(NOT _gmssl_x509_short_serial_guard EQUAL -1)
    message(FATAL_ERROR "GmSSL short X.509 serial compatibility adaptation missing")
endif()
string(FIND "${_gmssl_x509_after}"
    "x509_validity_check(not_before, not_after, now, -1)"
    _gmssl_x509_validity_guard)
if(_gmssl_x509_validity_guard EQUAL -1)
    message(FATAL_ERROR "GmSSL X.509 RFC 5280 validity adaptation missing")
endif()
unset(_gmssl_x509_validity_guard)
unset(_gmssl_x509_short_serial_guard)
unset(_gmssl_x509_after)
unset(_gmssl_x509_c)

