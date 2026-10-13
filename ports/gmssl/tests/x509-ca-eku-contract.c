#include <gmssl/x509_cer.h>
#include <gmssl/x509_ext.h>

#include <stdint.h>
#include <stdio.h>
#include <time.h>

int main(void)
{
	uint8_t exts[256];
	size_t extslen = 0;
	const int server_auth[] = { OID_kp_server_auth };
	time_t now = time(NULL);

	if (x509_exts_add_basic_constraints(exts, &extslen, sizeof(exts),
			X509_critical, 1, 0) != 1) return 1;
	if (x509_exts_add_key_usage(exts, &extslen, sizeof(exts),
			X509_critical, X509_KU_KEY_CERT_SIGN | X509_KU_CRL_SIGN) != 1) return 2;
	if (x509_exts_add_ext_key_usage(exts, &extslen, sizeof(exts),
			X509_non_critical, server_auth,
			sizeof(server_auth)/sizeof(server_auth[0])) != 1) return 3;

	/* A CA EKU constrains issued paths; it is valid CA structure rather than a
	 * request to use the CA certificate as the TLS server leaf. */
	if (x509_exts_check(exts, extslen, X509_cert_ca) != 1) return 4;
	if (x509_ext_key_usage_check(server_auth,
			sizeof(server_auth)/sizeof(server_auth[0]),
			X509_cert_server_auth) != 1) return 5;
	if (x509_ext_key_usage_check(server_auth,
			sizeof(server_auth)/sizeof(server_auth[0]),
			X509_cert_client_auth) == 1) return 6;
	if (x509_validity_check(now - 1,
			now + X509_VALIDITY_MAX_SECONDS + 1,
			now, X509_VALIDITY_MAX_SECONDS) == 1) return 7;
	if (x509_validity_check(now - 1,
			now + X509_VALIDITY_MAX_SECONDS + 1,
			now, -1) != 1) return 8;

	puts("GmSSL X.509 CA extended-key-usage contract: PASS");
	return 0;
}
