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
