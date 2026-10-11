# Bounded RSA private CRT with fixed-width arithmetic, random blinding and
# result verification. Keep the existing public ABI; own the implementation in
# a normal provider source file rather than embedding it in a CMake string.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
[==[
int rsa_private_key_from_der(RSA_PRIVATE_KEY *key, const uint8_t **in, size_t *inlen);
int rsa_private_key_operation(const RSA_PRIVATE_KEY *key,
	const uint8_t *in, size_t inlen,
	uint8_t *out, size_t outmax, size_t *outlen);
void rsa_private_key_cleanup(RSA_PRIVATE_KEY *key);
]==]
)

file(COPY "${CMAKE_CURRENT_LIST_DIR}/rsa_private_op.c"
     DESTINATION "${SOURCE_PATH}/src")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/rsa_components.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c" "src/debug.c\nsrc/rsa_private_op.c")
unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
