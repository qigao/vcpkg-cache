# Without SNI, certificate selection must receive the empty (NULL, 0) hostname
# view. TLS 1.2 already initializes this length; match that contract for TLS 1.3.
gmssl_replace_once(
    "${SOURCE_PATH}/src/tls13.c"
[==[
	const uint8_t *host_name = NULL;
	size_t host_name_len;
]==]
[==[
	const uint8_t *host_name = NULL;
	size_t host_name_len = 0;
]==]
)

# Missing client identity and signature_algorithms_cert are valid inputs to a
# CertificateRequest. Do not let absent optional state reach certificate selection
# as uninitialized flags or counts.
gmssl_replace_once(
    "${SOURCE_PATH}/src/tls13.c"
[==[
	int client_cert;
]==]
[==[
	int client_cert = 0;
]==]
)
gmssl_replace_once(
    "${SOURCE_PATH}/src/tls13.c"
[==[
	int common_sig_algs_cert[4];
	size_t common_sig_algs_cert_cnt;
]==]
[==[
	int common_sig_algs_cert[4];
	size_t common_sig_algs_cert_cnt = 0;
]==]
)
