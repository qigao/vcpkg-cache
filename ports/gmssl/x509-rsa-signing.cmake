# RSA private identity ownership and PKCS#1 SHA-256 signing through X509_KEY.
# Keeps RSA public verification storage unchanged and adds a bounded sidecar
# private key only when an identity is loaded.

set(_gmssl_x509_h "${SOURCE_PATH}/include/gmssl/x509_key.h")
set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_x509_h}"
[==[
	} u;
} X509_KEY;
]==]
[==[
	} u;
	RSA_PRIVATE_KEY rsa_private_key;
	int has_private_key;
} X509_KEY;
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
void x509_key_cleanup(X509_KEY *key)
{
	if (key) {
]==]
[==[
void x509_key_cleanup(X509_KEY *key)
{
	if (key) {
		if (key->algor == OID_rsa_encryption && key->has_private_key) {
			rsa_private_key_cleanup(&key->rsa_private_key);
			key->has_private_key = 0;
		}
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
	if (!key || !fp) {
		error_print();
		return -1;
	}

	if (algor == OID_ec_public_key) {
]==]
[==[
int x509_private_key_from_file(X509_KEY *key, int algor, const char *pass, FILE *fp)
{
	if (!key || !fp) {
		error_print();
		return -1;
	}

	if (algor == OID_rsa_encryption) {
		RSA_PRIVATE_KEY private_key;
		memset(&private_key, 0, sizeof(private_key));
		if (rsa_private_key_info_from_pem(&private_key, fp) != 1) {
			rsa_private_key_cleanup(&private_key);
			error_print();
			return -1;
		}
		memset(key, 0, sizeof(*key));
		key->algor = OID_rsa_encryption;
		key->algor_param = OID_undef;
		key->u.rsa_public_key = private_key.public_key;
		key->rsa_private_key = private_key;
		key->has_private_key = 1;
		gmssl_secure_clear(&private_key, sizeof(private_key));
		return 1;
	}

	if (algor == OID_ec_public_key) {
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	memset(ctx, 0, sizeof(X509_SIGN_CTX));

	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
	memset(ctx, 0, sizeof(X509_SIGN_CTX));

	switch (key->algor) {
	case OID_rsa_encryption:
		if (args || argslen || !key->has_private_key
			|| key->rsa_private_key.public_key.modulus_size != key->u.rsa_public_key.modulus_size
			|| key->rsa_private_key.public_key.public_exponent != key->u.rsa_public_key.public_exponent
			|| gmssl_secure_memcmp(key->rsa_private_key.public_key.modulus,
				key->u.rsa_public_key.modulus,
				key->u.rsa_public_key.modulus_size) != 0) {
			error_print();
			return -1;
		}
		sha256_init(&ctx->u.rsa_verify_ctx);
		ctx->key = *key;
		ctx->sign_algor = OID_rsasign_with_sha256;
		break;
	case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_sign_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	if (!ctx) {
		error_print();
		return -1;
	}

	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
]==]
[==[
int x509_sign_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	if (!ctx) {
		error_print();
		return -1;
	}

	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
		sha256_update(&ctx->u.rsa_verify_ctx, data, datalen);
		break;
	case OID_sm2sign_with_sm3:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_sign_finish(X509_SIGN_CTX *ctx, uint8_t *sig, size_t *siglen)
{
	if (!ctx || !sig || !siglen) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
		if (ctx->fixed_siglen) {
]==]
[==[
int x509_sign_finish(X509_SIGN_CTX *ctx, uint8_t *sig, size_t *siglen)
{
	if (!ctx || !sig || !siglen) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256: {
		uint8_t dgst[SHA256_DIGEST_SIZE];
		int ret;
		sha256_finish(&ctx->u.rsa_verify_ctx, dgst);
		ret = rsa_sign_pkcs1_v15_sha256(&ctx->key.rsa_private_key,
			dgst, sig, ctx->key.u.rsa_public_key.modulus_size, siglen);
		gmssl_secure_clear(dgst, sizeof(dgst));
		if (ret != 1) {
			error_print();
			return -1;
		}
		break;
	}
	case OID_sm2sign_with_sm3:
		if (ctx->fixed_siglen) {
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
int x509_sign(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen, uint8_t *sig, size_t *siglen)
{
	if (!ctx || !sig || !siglen) {
		error_print();
		return -1;
	}
	if (!data || !datalen) {
		error_print();
		return -1;
	}

	switch (ctx->sign_algor) {
	case OID_sm2sign_with_sm3:
#ifdef ENABLE_SECP256R1
]==]
[==[
int x509_sign(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen, uint8_t *sig, size_t *siglen)
{
	if (!ctx || !sig || !siglen) {
		error_print();
		return -1;
	}
	if (!data || !datalen) {
		error_print();
		return -1;
	}

	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
	case OID_sm2sign_with_sm3:
#ifdef ENABLE_SECP256R1
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			break;
]==]
[==[
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			x509_key_cleanup(&ctx->key);
			break;
]==]
)

unset(_gmssl_x509_h)
unset(_gmssl_x509_c)
