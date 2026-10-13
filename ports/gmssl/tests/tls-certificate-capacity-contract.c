#include <gmssl/tls.h>

#include <stdio.h>

int main(void)
{
	if (TLS_MAX_CERTIFICATES_SIZE < 8192) return 1;
	if (sizeof(((TLS_CONNECT *)0)->peer_cert_chain) != TLS_MAX_CERTIFICATES_SIZE) return 2;
	if (sizeof(((TLS_CONNECT *)0)->client_certs) != TLS_MAX_CERTIFICATES_SIZE) return 3;

	puts("GmSSL TLS certificate-chain capacity contract: PASS");
	return 0;
}
