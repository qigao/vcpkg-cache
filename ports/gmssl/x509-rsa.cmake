# X.509 RSA public-key storage and SHA-256 certificate verification.
#
# Keep RSA signing unsupported: this adapts verification/public-key paths only.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")
set(_gmssl_x509_h "${SOURCE_PATH}/include/gmssl/x509_key.h")
set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")
set(_gmssl_x509_vrf_c "${SOURCE_PATH}/src/x509_vrf.c")

# Round-trip PKCS#1 RSAPublicKey DER is required by X509 public-key APIs.
vcpkg_replace_string(
    "${_gmssl_rsa_h}"
    "int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);"
    "int rsa_public_key_to_der(const RSA_PUBLIC_KEY *key, uint8_t **out, size_t *outlen);\nint rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);"
)

vcpkg_replace_string(
    "${_gmssl_rsa_c}"
    "int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen)\n{"
    [==[
int rsa_public_key_to_der(const RSA_PUBLIC_KEY *key, uint8_t **out, size_t *outlen)
{
	size_t len = 0;

	if (!key || !outlen
		|| key->modulus_size < RSA_MIN_MODULUS_SIZE
		|| key->modulus_size > RSA_MAX_MODULUS_SIZE
		|| (key->modulus_size & 3u) != 0
		|| key->modulus[0] == 0
		|| (key->modulus[key->modulus_size - 1] & 1u) == 0
		|| key->public_exponent < 3
		|| key->public_exponent > 0x7fffffffu
		|| (key->public_exponent & 1u) == 0) {
		error_print();
		return -1;
	}
	if (asn1_integer_to_der(key->modulus, key->modulus_size, NULL, &len) != 1
		|| asn1_int_to_der((int)key->public_exponent, NULL, &len) != 1
		|| asn1_sequence_header_to_der(len, out, outlen) != 1
		|| asn1_integer_to_der(key->modulus, key->modulus_size, out, outlen) != 1
		|| asn1_int_to_der((int)key->public_exponent, out, outlen) != 1) {
		error_print();
		return -1;
	}
	return 1;
}

int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen)
{
]==]
)

# X509_KEY owns the parsed RSA public key as a normal value.
vcpkg_replace_string(
    "${_gmssl_x509_h}"
    "#include <gmssl/digest.h>\n#include <gmssl/sm2.h>"
    "#include <gmssl/digest.h>\n#include <gmssl/rsa.h>\n#include <gmssl/sm2.h>"
)

vcpkg_replace_string(
    "${_gmssl_x509_h}"
    "union {\n\t\tSM2_KEY sm2_key;"
    "union {\n\t\tRSA_PUBLIC_KEY rsa_public_key;\n\t\tSM2_KEY sm2_key;"
)

vcpkg_replace_string(
    "${_gmssl_x509_h}"
    "int x509_key_set_sm2_key(X509_KEY *x509_key, const SM2_KEY *sm2_key);"
    "int x509_key_set_rsa_public_key(X509_KEY *x509_key, const RSA_PUBLIC_KEY *rsa_public_key);\nint x509_key_set_sm2_key(X509_KEY *x509_key, const SM2_KEY *sm2_key);"
)

# RSA verification streams SHA-256 through the existing X509_SIGN_CTX API.
vcpkg_replace_string(
    "${_gmssl_x509_h}"
    "union {\n\t\tSM2_SIGN_CTX sm2_sign_ctx;"
    "union {\n\t\tSHA256_CTX rsa_verify_ctx;\n\t\tSM2_SIGN_CTX sm2_sign_ctx;"
)

vcpkg_replace_string(
    "${_gmssl_x509_h}"
    "int x509_key_get_sign_algor(const X509_KEY *key, int *algor);"
    "int x509_key_supports_sign_algor(const X509_KEY *key, int algor);\nint x509_key_get_sign_algor(const X509_KEY *key, int *algor);"
)

vcpkg_replace_string(
    "${_gmssl_x509_h}"
    "int x509_verify_init(X509_SIGN_CTX *ctx, const X509_KEY *key, const void *args, size_t argslen,\n\tconst uint8_t *sig, size_t siglen);"
    "int x509_verify_init_ex(X509_SIGN_CTX *ctx, const X509_KEY *key, int sign_algor,\n\tconst void *args, size_t argslen, const uint8_t *sig, size_t siglen);\nint x509_verify_init(X509_SIGN_CTX *ctx, const X509_KEY *key, const void *args, size_t argslen,\n\tconst uint8_t *sig, size_t siglen);"
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "int x509_key_set_sm2_key(X509_KEY *x509_key, const SM2_KEY *sm2_key)\n{"
    [==[
int x509_key_set_rsa_public_key(X509_KEY *x509_key, const RSA_PUBLIC_KEY *rsa_public_key)
{
	if (!x509_key || !rsa_public_key) {
		error_print();
		return -1;
	}
	memset(x509_key, 0, sizeof(*x509_key));
	x509_key->algor = OID_rsa_encryption;
	x509_key->algor_param = OID_undef;
	x509_key->u.rsa_public_key = *rsa_public_key;
	return 1;
}

int x509_key_set_sm2_key(X509_KEY *x509_key, const SM2_KEY *sm2_key)
{
]==]
)

# Cleanup, byte encoding/parsing and equality.
vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (key->algor) {\n\t\tcase OID_ec_public_key:"
    "switch (key->algor) {\n\t\tcase OID_rsa_encryption:\n\t\t\tgmssl_secure_clear(&key->u.rsa_public_key, sizeof(RSA_PUBLIC_KEY));\n\t\t\tbreak;\n\t\tcase OID_ec_public_key:"
    COUNT 1
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (key->algor) {\n\tcase OID_ec_public_key:"
    "switch (key->algor) {\n\tcase OID_rsa_encryption:\n\t\tif (rsa_public_key_to_der(&key->u.rsa_public_key, out, outlen) != 1) {\n\t\t\terror_print();\n\t\t\treturn -1;\n\t\t}\n\t\tbreak;\n\tcase OID_ec_public_key:"
    COUNT 1
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (algor) {\n\tcase OID_ec_public_key:"
    "switch (algor) {\n\tcase OID_rsa_encryption:\n\t\tif (algor_param != OID_undef\n\t\t\t|| rsa_public_key_from_der(&key->u.rsa_public_key, in, inlen) != 1) {\n\t\t\terror_print();\n\t\t\treturn -1;\n\t\t}\n\t\treturn 1;\n\tcase OID_ec_public_key:"
    COUNT 1
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "if (key->algor != pub->algor) {"
    "if (key->algor != pub->algor) {"
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (key->algor) {\n\tcase OID_ec_public_key:\n\t\tif (key->algor_param == OID_sm2) {"
    "switch (key->algor) {\n\tcase OID_rsa_encryption:\n\t\tif (key->u.rsa_public_key.modulus_size != pub->u.rsa_public_key.modulus_size\n\t\t\t|| key->u.rsa_public_key.public_exponent != pub->u.rsa_public_key.public_exponent\n\t\t\t|| gmssl_secure_memcmp(key->u.rsa_public_key.modulus, pub->u.rsa_public_key.modulus,\n\t\t\t\tkey->u.rsa_public_key.modulus_size) != 0) return 0;\n\t\treturn 1;\n\tcase OID_ec_public_key:\n\t\tif (key->algor_param == OID_sm2) {"
    COUNT 1
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (key->algor) {\n\tcase OID_ec_public_key:\n\t\tif (key->algor_param == OID_sm2) {"
    "switch (key->algor) {\n\tcase OID_rsa_encryption: {\n\t\tuint8_t der[RSA_MAX_MODULUS_SIZE + 32];\n\t\tuint8_t *p = der;\n\t\tsize_t derlen = 0;\n\t\tif (rsa_public_key_to_der(&key->u.rsa_public_key, &p, &derlen) != 1\n\t\t\t|| rsa_public_key_print(fp, fmt, ind, label, der, derlen) != 1) {\n\t\t\terror_print();\n\t\t\treturn -1;\n\t\t}\n\t\tbreak;\n\t}\n\tcase OID_ec_public_key:\n\t\tif (key->algor_param == OID_sm2) {"
    COUNT 1
)

# RSA key supports SHA-256 PKCS#1 verification; signing remains unsupported.
vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "int x509_key_get_sign_algor(const X509_KEY *key, int *algor)\n{"
    [==[
int x509_key_supports_sign_algor(const X509_KEY *key, int algor)
{
	int default_algor;
	if (!key) {
		error_print();
		return -1;
	}
	if (key->algor == OID_rsa_encryption) {
		return algor == OID_rsasign_with_sha256 ? 1 : 0;
	}
	if (x509_key_get_sign_algor(key, &default_algor) != 1) {
		return -1;
	}
	return algor == default_algor ? 1 : 0;
}

int x509_key_get_sign_algor(const X509_KEY *key, int *algor)
{
]==]
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (key->algor) {\n\tcase OID_ec_public_key:"
    "switch (key->algor) {\n\tcase OID_rsa_encryption:\n\t\t*algor = OID_rsasign_with_sha256;\n\t\tbreak;\n\tcase OID_ec_public_key:"
    COUNT 1
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (key->algor) {\n\tcase OID_ec_public_key:\n\t\t*siglen = SM2_signature_max_size;"
    "switch (key->algor) {\n\tcase OID_rsa_encryption:\n\t\t*siglen = key->u.rsa_public_key.modulus_size;\n\t\tbreak;\n\tcase OID_ec_public_key:\n\t\t*siglen = SM2_signature_max_size;"
    COUNT 1
)

# Add algorithm-explicit verification while preserving the old wrapper.
vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "int x509_verify_init(X509_SIGN_CTX *ctx, const X509_KEY *key, const void *args, size_t argslen,\n\tconst uint8_t *sig, size_t siglen)\n{"
    [==[
int x509_verify_init_ex(X509_SIGN_CTX *ctx, const X509_KEY *key, int sign_algor,
	const void *args, size_t argslen, const uint8_t *sig, size_t siglen)
{
]==]
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "memset(ctx, 0, sizeof(X509_SIGN_CTX));\n\n\tswitch (key->algor) {"
    "memset(ctx, 0, sizeof(X509_SIGN_CTX));\n\n\tif (x509_key_supports_sign_algor(key, sign_algor) != 1) {\n\t\treturn -1;\n\t}\n\n\tswitch (key->algor) {"
    COUNT 1
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (key->algor) {\n\tcase OID_ec_public_key:"
    "switch (key->algor) {\n\tcase OID_rsa_encryption:\n\t\tif (args || argslen || sign_algor != OID_rsasign_with_sha256\n\t\t\t|| siglen != key->u.rsa_public_key.modulus_size) {\n\t\t\terror_print();\n\t\t\treturn -1;\n\t\t}\n\t\tsha256_init(&ctx->u.rsa_verify_ctx);\n\t\tctx->key = *key;\n\t\tctx->sign_algor = sign_algor;\n\t\tctx->sig = sig;\n\t\tctx->siglen = siglen;\n\t\tbreak;\n\tcase OID_ec_public_key:"
    COUNT 1
)

# Existing EC/default code assigns its own sign_algor; require the requested one.
vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "return 1;\n}\n\nint x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)"
    [==[
	return 1;
}

int x509_verify_init(X509_SIGN_CTX *ctx, const X509_KEY *key, const void *args, size_t argslen,
	const uint8_t *sig, size_t siglen)
{
	int sign_algor;
	if (x509_key_get_sign_algor(key, &sign_algor) != 1) {
		return -1;
	}
	return x509_verify_init_ex(ctx, key, sign_algor, args, argslen, sig, siglen);
}

int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
]==]
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (ctx->sign_algor) {\n\tcase OID_sm2sign_with_sm3:"
    "switch (ctx->sign_algor) {\n\tcase OID_rsasign_with_sha256:\n\t\tsha256_update(&ctx->u.rsa_verify_ctx, data, datalen);\n\t\tbreak;\n\tcase OID_sm2sign_with_sm3:"
    COUNT 1
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (ctx->sign_algor) {\n\tcase OID_sm2sign_with_sm3:"
    "switch (ctx->sign_algor) {\n\tcase OID_rsasign_with_sha256: {\n\t\tuint8_t dgst[SHA256_DIGEST_SIZE];\n\t\tsha256_finish(&ctx->u.rsa_verify_ctx, dgst);\n\t\tret = rsa_verify_pkcs1_v15_sha256(&ctx->key.u.rsa_public_key,\n\t\t\tdgst, ctx->sig, ctx->siglen);\n\t\tgmssl_secure_clear(dgst, sizeof(dgst));\n\t\tif (ret < 0) return -1;\n\t\tbreak;\n\t}\n\tcase OID_sm2sign_with_sm3:"
    COUNT 1
)

vcpkg_replace_string(
    "${_gmssl_x509_c}"
    "switch (ctx->sign_algor) {\n\t\tcase OID_sm2sign_with_sm3:"
    "switch (ctx->sign_algor) {\n\t\tcase OID_rsasign_with_sha256:\n\t\t\tgmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));\n\t\t\tbreak;\n\t\tcase OID_sm2sign_with_sm3:"
    COUNT 1
)

# Certificate verification must use the signatureAlgorithm actually encoded by
# the certificate instead of assuming one algorithm per key.
vcpkg_replace_string(
    "${_gmssl_x509_vrf_c}"
    "int key_sig_alg;\n\tvoid *sign_args = NULL;"
    "void *sign_args = NULL;"
)

vcpkg_replace_string(
    "${_gmssl_x509_vrf_c}"
    "// FIXME: 改为 x509_key_support_algor\n\tif (x509_key_get_sign_algor(key, &key_sig_alg) != 1) {\n\t\terror_print();\n\t\treturn -1;\n\t}\n\tif (sig_alg != key_sig_alg) {\n\t\treturn 0;\n\t}"
    "if (x509_key_supports_sign_algor(key, sig_alg) != 1) {\n\t\treturn 0;\n\t}"
)

vcpkg_replace_string(
    "${_gmssl_x509_vrf_c}"
    "if (x509_verify_init(&verify_ctx, key, sign_args, sign_argslen, sig, siglen) != 1"
    "if (x509_verify_init_ex(&verify_ctx, key, sig_alg, sign_args, sign_argslen, sig, siglen) != 1"
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
unset(_gmssl_x509_h)
unset(_gmssl_x509_c)
unset(_gmssl_x509_vrf_c)
