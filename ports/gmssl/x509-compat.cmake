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
