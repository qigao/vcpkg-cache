#include <gmssl/x509_ext.h>
#include <gmssl/x509_cer.h>

#include <stdint.h>
#include <stdio.h>

int main(void)
{
	static const uint8_t empty_basic_constraints[] = { 0x30, 0x00 };
	const uint8_t *p = empty_basic_constraints;
	size_t len = sizeof(empty_basic_constraints);
	int ca = -7;
	int path_len = -7;

	if (x509_basic_constraints_from_der(&ca, &path_len, &p, &len) != 1) return 1;
	if (ca != 0) return 2;
	if (path_len != -1) return 3;
	if (len != 0) return 4;
	if (p != empty_basic_constraints + sizeof(empty_basic_constraints)) return 5;
	if (x509_basic_constraints_check(ca, path_len, X509_cert_server_auth) != 1) return 6;

	puts("GmSSL X.509 default BasicConstraints contract: PASS");
	return 0;
}
