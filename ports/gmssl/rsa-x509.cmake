# Add RSA public-key storage to X509_KEY and SubjectPublicKeyInfo parsing.
# This layer depends only on the raw bounded RSA public-key representation.

set(_gmssl_rsa_h "${SOURCE_PATH}/include/gmssl/rsa.h")
set(_gmssl_rsa_c "${SOURCE_PATH}/src/rsa.c")
set(_gmssl_x509_key_h "${SOURCE_PATH}/include/gmssl/x509_key.h")
set(_gmssl_x509_key_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_rsa_h}"
[==[
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);
int rsa_public_key_operation(const RSA_PUBLIC_KEY *key,
]==]
[==[
int rsa_public_key_to_der(const RSA_PUBLIC_KEY *key, uint8_t **out, size_t *outlen);
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen);
int rsa_public_key_operation(const RSA_PUBLIC_KEY *key,
]==]
)

gmssl_replace_once(
    "${_gmssl_rsa_c}"
[==[
int rsa_public_key_from_der(RSA_PUBLIC_KEY *key, const uint8_t **in, size_t *inlen)
]==]
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
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_key_h}"
[==[
#include <gmssl/digest.h>
#include <gmssl/sm2.h>
]==]
[==[
#include <gmssl/digest.h>
#include <gmssl/rsa.h>
#include <gmssl/sm2.h>
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_key_h}"
[==[
	union {
		SM2_KEY sm2_key;
]==]
[==[
	union {
		RSA_PUBLIC_KEY rsa_public_key;
		SM2_KEY sm2_key;
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_key_c}"
[==[
		switch (key->algor) {
		case OID_ec_public_key:
]==]
[==[
		switch (key->algor) {
		case OID_rsa_encryption:
			gmssl_secure_clear(&key->u.rsa_public_key, sizeof(RSA_PUBLIC_KEY));
			break;
		case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_key_c}"
[==[
	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
	switch (key->algor) {
	case OID_rsa_encryption:
		if (rsa_public_key_to_der(&key->u.rsa_public_key, out, outlen) != 1) {
			error_print();
			return -1;
		}
		break;
	case OID_ec_public_key:
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_key_c}"
[==[
	switch (algor) {
#ifdef ENABLE_LMS
]==]
[==[
	switch (algor) {
	case OID_rsa_encryption:
		if (rsa_public_key_from_der(&key->u.rsa_public_key, in, inlen) != 1) {
			error_print();
			return -1;
		}
		break;
#ifdef ENABLE_LMS
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_key_c}"
[==[
	switch (key->algor) {
	case OID_ec_public_key:
		if (key->algor_param == OID_sm2) {
]==]
[==[
	switch (key->algor) {
	case OID_rsa_encryption:
		if (key->u.rsa_public_key.modulus_size != pub->u.rsa_public_key.modulus_size
			|| key->u.rsa_public_key.public_exponent != pub->u.rsa_public_key.public_exponent
			|| memcmp(key->u.rsa_public_key.modulus,
				pub->u.rsa_public_key.modulus,
				key->u.rsa_public_key.modulus_size) != 0) {
			return 0;
		}
		return 1;
	case OID_ec_public_key:
		if (key->algor_param == OID_sm2) {
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_key_c}"
[==[
int x509_public_key_print(FILE *fp, int fmt, int ind, const char *label, const X509_KEY *key)
{
	switch (key->algor) {
	case OID_ec_public_key:
]==]
[==[
int x509_public_key_print(FILE *fp, int fmt, int ind, const char *label, const X509_KEY *key)
{
	switch (key->algor) {
	case OID_rsa_encryption:
		{
			uint8_t der[RSA_MAX_MODULUS_SIZE + 32];
			uint8_t *p = der;
			size_t len = 0;
			if (rsa_public_key_to_der(&key->u.rsa_public_key, &p, &len) != 1
				|| rsa_public_key_print(fp, fmt, ind, label, der, len) != 1) {
				error_print();
				return -1;
			}
		}
		break;
	case OID_ec_public_key:
]==]
)

unset(_gmssl_rsa_h)
unset(_gmssl_rsa_c)
unset(_gmssl_x509_key_h)
unset(_gmssl_x509_key_c)
