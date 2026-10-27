# GmSSL port source transformations (phase 4/4): P384, ABI and security hardening.
# Order-preserving consolidation: original source-bearing C/H inputs are now pinned in qigao/crypto.

# --- begin original tls13-fatal-alert.cmake (Git blob 575ba319d7f927f4af0720c5afb934f6891e4a39) ---
# GmSSL TLS 1.3 reuses conn->record for both inbound and outbound records.
# After tls_recv_record() completes, recordlen/record_offset still describe
# the just-consumed ClientHello. In tls13_send_alert(), treating this as an
# outstanding outbound record skips alert encoding and tls_io_send() entirely.
#
# Clear *only* an already fully consumed record. A partial outbound send is
# still owned by the provider and must not be erased or retried implicitly.
# Fatal Alert code/level selection remains GmSSL's responsibility.
set(_gmssl_tls13_fatal_alert_c "${SOURCE_PATH}/src/tls13.c")

gmssl_replace_once(
    "${_gmssl_tls13_fatal_alert_c}"
[==[
int tls13_send_alert(TLS_CONNECT *conn, int alert)
{
	int ret;
	size_t padding_len;

	if(conn->verbose) tls_trace("send {Alert}\n");

	if (conn->recordlen == 0) {
]==]
[==[
int tls13_send_alert(TLS_CONNECT *conn, int alert)
{
	int ret;
	size_t padding_len;

	if(conn->verbose) tls_trace("send {Alert}\n");

	/* A complete inbound handshake record must not be mistaken for a
	 * pending outbound alert record. Preserve any partially sent record. */
	if (conn->recordlen != 0 && conn->record_offset == conn->recordlen) {
		tls_clean_record(conn);
	}

	if (conn->recordlen == 0) {
]==]
)

unset(_gmssl_tls13_fatal_alert_c)
# --- end original tls13-fatal-alert.cmake ---

# --- begin original x509-p384-sha384.cmake (Git blob d6e27e55cb4b19e4fb3ba542a56ddd4c3f921d31) ---
# Verify-only P-384 / ECDSA-SHA384 backport for X.509 issuing CA chains.
# Source: guanzhi/GmSSL 24ae482701a7b124826c382fffc55c19f76d475d (Apache-2.0), trimmed to verifier.
# No P-384 TLS key agreement, no new TLS scheduler, no OpenSSL fallback.

configure_file("${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/src/secp384r1_verify.c"
               "${SOURCE_PATH}/src/secp384r1.c" COPYONLY)
configure_file("${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/include/gmssl/secp384r1_verify.h"
               "${SOURCE_PATH}/include/gmssl/secp384r1.h" COPYONLY)

set(_gmssl_p384_cmake "${SOURCE_PATH}/CMakeLists.txt")
set(_gmssl_p384_h "${SOURCE_PATH}/include/gmssl/x509_key.h")
set(_gmssl_p384_c "${SOURCE_PATH}/src/x509_key.c")

gmssl_replace_once(
    "${_gmssl_p384_cmake}"
[==[
	list(APPEND src src/bn.c src/secp256r1.c src/secp256r1_key.c src/ecdsa.c src/ecdh.c)
]==]
[==[
	add_definitions(-DENABLE_SECP384R1)
	list(APPEND src src/bn.c src/secp256r1.c src/secp256r1_key.c src/ecdsa.c src/ecdh.c src/secp384r1.c)
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_h}"
[==[
#include <gmssl/ecdsa.h>
#endif
]==]
[==[
#include <gmssl/ecdsa.h>
#endif
#ifdef ENABLE_SECP384R1
#include <gmssl/secp384r1.h>
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_h}"
[==[
		SECP256R1_KEY secp256r1_key;
#endif
]==]
[==[
		SECP256R1_KEY secp256r1_key;
#endif
#ifdef ENABLE_SECP384R1
		SECP384R1_KEY secp384r1_key;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_h}"
[==[
		ECDSA_SIGN_CTX ecdsa_sign_ctx;
#endif
]==]
[==[
		ECDSA_SIGN_CTX ecdsa_sign_ctx;
#endif
#ifdef ENABLE_SECP384R1
		SECP384R1_ECDSA_SIGN_CTX ecdsa_p384_verify_ctx;
		SHA384_CTX ecdsa_p256_sha384_ctx;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_secp256r1:
			if (secp256r1_public_key_to_bytes(&key->u.secp256r1_key, out, outlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
]==]
[==[
		case OID_secp256r1:
			if (secp256r1_public_key_to_bytes(&key->u.secp256r1_key, out, outlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
#ifdef ENABLE_SECP384R1
		case OID_secp384r1:
			if (secp384r1_public_key_to_bytes(&key->u.secp384r1_key, out, outlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_secp256r1:
			if (secp256r1_public_key_from_bytes(&key->u.secp256r1_key, in, inlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
]==]
[==[
		case OID_secp256r1:
			if (secp256r1_public_key_from_bytes(&key->u.secp256r1_key, in, inlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
#ifdef ENABLE_SECP384R1
		case OID_secp384r1:
			if (secp384r1_public_key_from_bytes(&key->u.secp384r1_key, in, inlen) != 1) {
				error_print();
				return -1;
			}
			break;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		} else if (key->algor_param == OID_secp256r1) {
			if ((ret = secp256r1_public_key_equ(&key->u.secp256r1_key, &pub->u.secp256r1_key)) != 1) {
				error_print();
				return ret;
			}
#endif
]==]
[==[
		} else if (key->algor_param == OID_secp256r1) {
			if ((ret = secp256r1_public_key_equ(&key->u.secp256r1_key, &pub->u.secp256r1_key)) != 1) {
				error_print();
				return ret;
			}
#endif
#ifdef ENABLE_SECP384R1
		} else if (key->algor_param == OID_secp384r1) {
			if ((ret = secp384r1_public_key_equ(&key->u.secp384r1_key, &pub->u.secp384r1_key)) != 1) {
				error_print();
				return ret;
			}
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
	if (x509_key_get_sign_algor(key, &default_algor) != 1) {
]==]
[==[
#ifdef ENABLE_SECP384R1
	if (key->algor == OID_ec_public_key && key->algor_param == OID_secp384r1)
		return algor == OID_ecdsa_with_sha384 ? 1 : 0;
	if (key->algor == OID_ec_public_key && key->algor_param == OID_secp256r1)
		return algor == OID_ecdsa_with_sha256 || algor == OID_ecdsa_with_sha384 ? 1 : 0;
#endif
	if (x509_key_get_sign_algor(key, &default_algor) != 1) {
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_secp256r1:
			*algor = OID_ecdsa_with_sha256;
			break;
#endif
]==]
[==[
		case OID_secp256r1:
			*algor = OID_ecdsa_with_sha256;
			break;
#endif
#ifdef ENABLE_SECP384R1
		case OID_secp384r1:
			*algor = OID_ecdsa_with_sha384;
			break;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_secp256r1:
			if (ecdsa_verify_init(&ctx->u.ecdsa_sign_ctx, &key->u.secp256r1_key, sig, siglen) != 1) {
				error_print();
				return -1;
			}
			ctx->sign_algor = OID_ecdsa_with_sha256;
			break;
#endif
]==]
[==[
		case OID_secp256r1:
#ifdef ENABLE_SECP384R1
			if (sign_algor == OID_ecdsa_with_sha384) {
				sha384_init(&ctx->u.ecdsa_p256_sha384_ctx);
				ctx->key = *key;
				ctx->sig = sig;
				ctx->siglen = siglen;
				ctx->sign_algor = OID_ecdsa_with_sha384;
				break;
			}
#endif
			if (ecdsa_verify_init(&ctx->u.ecdsa_sign_ctx, &key->u.secp256r1_key, sig, siglen) != 1) {
				error_print();
				return -1;
			}
			ctx->sign_algor = OID_ecdsa_with_sha256;
			break;
#endif
#ifdef ENABLE_SECP384R1
		case OID_secp384r1:
			if (secp384r1_ecdsa_verify_init(&ctx->u.ecdsa_p384_verify_ctx,
				&key->u.secp384r1_key, DIGEST_sha384(), sig, siglen) != 1)
				return -1;
			ctx->key = *key;
			ctx->sign_algor = OID_ecdsa_with_sha384;
			break;
#endif
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
]==]
[==[
int x509_verify_update(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	switch (ctx->sign_algor) {
#ifdef ENABLE_SECP384R1
	case OID_ecdsa_with_sha384:
		if (ctx->key.algor_param == OID_secp384r1) {
			if (secp384r1_ecdsa_verify_update(&ctx->u.ecdsa_p384_verify_ctx, data, datalen) != 1)
				return -1;
		} else if (ctx->key.algor_param == OID_secp256r1) {
			sha384_update(&ctx->u.ecdsa_p256_sha384_ctx, data, datalen);
		} else return -1;
		break;
#endif
	case OID_rsasign_with_sha256:
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
int x509_verify_finish(X509_SIGN_CTX *ctx)
{
	int ret;
	const char *id;
	size_t idlen;

	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256: {
]==]
[==[
int x509_verify_finish(X509_SIGN_CTX *ctx)
{
	int ret;
	const char *id;
	size_t idlen;

	switch (ctx->sign_algor) {
#ifdef ENABLE_SECP384R1
	case OID_ecdsa_with_sha384:
		if (ctx->key.algor_param == OID_secp384r1) {
			ret = secp384r1_ecdsa_verify_finish(&ctx->u.ecdsa_p384_verify_ctx);
		} else if (ctx->key.algor_param == OID_secp256r1) {
			uint8_t dgst[SHA384_DIGEST_SIZE];
			sha384_finish(&ctx->u.ecdsa_p256_sha384_ctx, dgst);
			/* FIPS 186 ECDSA: leftmost 256 bits of SHA-384 digest for P-256. */
			ret = ecdsa_verify(&ctx->key.u.secp256r1_key, dgst, ctx->sig, ctx->siglen);
			gmssl_secure_clear(dgst, sizeof(dgst));
		} else return -1;
		if (ret != 1) return ret < 0 ? -1 : 0;
		break;
#endif
	case OID_rsasign_with_sha256: {
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
int x509_verify(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	int ret;

	if (!ctx) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
	case OID_rsasign_with_sha256:
]==]
[==[
int x509_verify(X509_SIGN_CTX *ctx, const uint8_t *data, size_t datalen)
{
	int ret;

	if (!ctx) {
		error_print();
		return -1;
	}
	switch (ctx->sign_algor) {
#ifdef ENABLE_SECP384R1
	case OID_ecdsa_with_sha384:
#endif
	case OID_rsasign_with_sha256:
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			x509_key_cleanup(&ctx->key);
			break;
]==]
[==[
		case OID_rsasign_with_sha256:
			gmssl_secure_clear(&ctx->u.rsa_verify_ctx, sizeof(SHA256_CTX));
			x509_key_cleanup(&ctx->key);
			break;
#ifdef ENABLE_SECP384R1
		case OID_ecdsa_with_sha384:
			gmssl_secure_clear(&ctx->u, sizeof(ctx->u));
			break;
#endif
]==]
)


# A P-384 public key is retained by X509_KEY; clean it on all paths.
gmssl_replace_once(
    "${_gmssl_p384_c}"
[==[
			case OID_secp256r1:
				secp256r1_key_cleanup(&key->u.secp256r1_key);
				break;
#endif
			default:
]==]
[==[
			case OID_secp256r1:
				secp256r1_key_cleanup(&key->u.secp256r1_key);
				break;
#endif
#ifdef ENABLE_SECP384R1
			case OID_secp384r1:
				gmssl_secure_clear(&key->u.secp384r1_key, sizeof(SECP384R1_KEY));
				break;
#endif
			default:
]==]
)

unset(_gmssl_p384_cmake)
unset(_gmssl_p384_h)
unset(_gmssl_p384_c)


# x509_cer.c has a second chain verifier distinct from the x509_vrf.c path
# already adapted by the RSA overlay. Both must respect the certificate's
# actual signed OID, not just the issuer key's default signing preference.
set(_gmssl_p384_cert_c "${SOURCE_PATH}/src/x509_cer.c")
gmssl_replace_once(
    "${_gmssl_p384_cert_c}"
[==[
	int key_sig_alg;
	void *sign_args = NULL;
]==]
[==[
	void *sign_args = NULL;
]==]
)
gmssl_replace_once(
    "${_gmssl_p384_cert_c}"
[==[
	if (x509_key_get_sign_algor(key, &key_sig_alg) != 1) {
		error_print();
		return -1;
	}
]==]
[==[
	/* Select the signature scheme from the certificate's DER OID below. */
]==]
)
gmssl_replace_once(
    "${_gmssl_p384_cert_c}"
[==[
	if (sig_alg != key_sig_alg) {
		error_print();
		return -1;
	}
]==]
[==[
	if (x509_key_supports_sign_algor(key, sig_alg) != 1) {
		error_print();
		return -1;
	}
]==]
)
gmssl_replace_once(
    "${_gmssl_p384_cert_c}"
[==[
	if (x509_verify_init(&verify_ctx, key, sign_args, sign_argslen, sig, siglen) != 1
]==]
[==[
	if (x509_verify_init_ex(&verify_ctx, key, sig_alg, sign_args, sign_argslen, sig, siglen) != 1
]==]
)
unset(_gmssl_p384_cert_c)

# TLS certificate-signature policy must understand P-384 issuing CA OIDs.
# SignatureScheme cert mapping is distinct from the ECDHE P-256 key-share group.
set(_gmssl_p384_tls_trace "${SOURCE_PATH}/src/tls_trace.c")
set(_gmssl_p384_tls12 "${SOURCE_PATH}/src/tls12.c")
set(_gmssl_p384_tls13 "${SOURCE_PATH}/src/tls13.c")


gmssl_replace_once(
    "${_gmssl_p384_tls_trace}"
[==[
	if (!strcmp(name, "ecdsa_secp256r1_sha256")) {
		return TLS_sig_ecdsa_secp256r1_sha256;
	} else if (!strcmp(name, "rsa_pkcs1_sha256")) {
]==]
[==[
	if (!strcmp(name, "ecdsa_secp256r1_sha256")) {
		return TLS_sig_ecdsa_secp256r1_sha256;
#ifdef ENABLE_SECP384R1
	} else if (!strcmp(name, "ecdsa_secp384r1_sha384")) {
		return TLS_sig_ecdsa_secp384r1_sha384;
#endif
	} else if (!strcmp(name, "rsa_pkcs1_sha256")) {
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_tls_trace}"
[==[
} else if (alg_oid == OID_ecdsa_with_sha256 && group_oid == OID_secp256r1) {
		return TLS_sig_ecdsa_secp256r1_sha256;
]==]
[==[
} else if (alg_oid == OID_ecdsa_with_sha256 && group_oid == OID_secp256r1) {
		return TLS_sig_ecdsa_secp256r1_sha256;
#ifdef ENABLE_SECP384R1
	} else if (alg_oid == OID_ecdsa_with_sha384 && group_oid == OID_secp384r1) {
		return TLS_sig_ecdsa_secp384r1_sha384;
#endif
]==]
)


gmssl_replace_once(
    "${_gmssl_p384_tls_trace}"
[==[
case TLS_sig_ecdsa_secp256r1_sha256: return OID_ecdsa_with_sha256;
]==]
[==[
case TLS_sig_ecdsa_secp256r1_sha256: return OID_ecdsa_with_sha256;
#ifdef ENABLE_SECP384R1
	case TLS_sig_ecdsa_secp384r1_sha384: return OID_ecdsa_with_sha384;
#endif
]==]
)


gmssl_replace_once(
    "${_gmssl_p384_tls_trace}"
[==[
case TLS_sig_ecdsa_secp256r1_sha256: return OID_secp256r1;
]==]
[==[
case TLS_sig_ecdsa_secp256r1_sha256: return OID_secp256r1;
#ifdef ENABLE_SECP384R1
	case TLS_sig_ecdsa_secp384r1_sha384: return OID_secp384r1;
#endif
]==]
)


gmssl_replace_once(
    "${_gmssl_p384_tls12}"
[==[
#if defined(ENABLE_SECP256R1) && defined(ENABLE_SHA2)
	TLS_sig_ecdsa_secp256r1_sha256,
#endif
]==]
[==[
#if defined(ENABLE_SECP256R1) && defined(ENABLE_SHA2)
	TLS_sig_ecdsa_secp256r1_sha256,
#endif
#ifdef ENABLE_SECP384R1
	TLS_sig_ecdsa_secp384r1_sha384,
#endif
]==]
)


gmssl_replace_once(
    "${_gmssl_p384_tls13}"
[==[
#if defined(ENABLE_SECP256R1) && defined(ENABLE_SHA2)
	TLS_sig_ecdsa_secp256r1_sha256,
#endif
]==]
[==[
#if defined(ENABLE_SECP256R1) && defined(ENABLE_SHA2)
	TLS_sig_ecdsa_secp256r1_sha256,
#endif
#ifdef ENABLE_SECP384R1
	TLS_sig_ecdsa_secp384r1_sha384,
#endif
]==]
)


gmssl_replace_once(
    "${_gmssl_p384_tls13}"
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		if (public_key->algor != OID_ec_public_key
			&& public_key->algor_param != OID_secp256r1) {
			error_print();
			return -1;
		}
		if (tbs_dgst_ctx->digest->oid != OID_sha256) {
			error_print();
			return -1;
		}
		break;
]==]
[==[
	case TLS_sig_ecdsa_secp256r1_sha256:
		if (public_key->algor != OID_ec_public_key
			&& public_key->algor_param != OID_secp256r1) {
			error_print();
			return -1;
		}
		if (tbs_dgst_ctx->digest->oid != OID_sha256) {
			error_print();
			return -1;
		}
		break;
#ifdef ENABLE_SECP384R1
	case TLS_sig_ecdsa_secp384r1_sha384:
		if (public_key->algor != OID_ec_public_key
			|| public_key->algor_param != OID_secp384r1
			|| tbs_dgst_ctx->digest->oid != OID_sha256) {
			error_print();
			return -1;
		}
		break;
#endif
]==]
)

# TLS 1.3 signature schemes bind *both* the public-key family and curve.
# The pinned provider used &&, which can admit an EC P-384 key while checking
# a claimed ecdsa_secp256r1_sha256 CertificateVerify. Require both match.
gmssl_replace_once(
    "${_gmssl_p384_tls13}"
[==[
		if (public_key->algor != OID_ec_public_key
			&& public_key->algor_param != OID_secp256r1) {
]==]
[==[
		if (public_key->algor != OID_ec_public_key
			|| public_key->algor_param != OID_secp256r1) {
]==]
)

gmssl_replace_once(
    "${_gmssl_p384_tls13}"
[==[
		if (public_key->algor != OID_ec_public_key
			&& public_key->algor_param != OID_sm2) {
]==]
[==[
		if (public_key->algor != OID_ec_public_key
			|| public_key->algor_param != OID_sm2) {
]==]
)

unset(_gmssl_p384_tls_trace)
unset(_gmssl_p384_tls12)
unset(_gmssl_p384_tls13)
# --- end original x509-p384-sha384.cmake ---

# --- begin original abi-contract.cmake (Git blob 3b5d39db836572c486769a6793633515163e342a) ---
# Expose runtime size probes for GmSSL's caller-owned public TLS structs.
# Their layout depends on public feature macros, so the package must be able to
# prove that consumer headers and the compiled library agree.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

vcpkg_replace_string(
    "${_gmssl_tls_h}"
    "int tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client);"
    "size_t tls_ctx_sizeof(void);\nint tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client);"
)

vcpkg_replace_string(
    "${_gmssl_tls_h}"
    "int tls_init(TLS_CONNECT *conn, TLS_CTX *ctx);"
    "size_t tls_connect_sizeof(void);\nint tls_init(TLS_CONNECT *conn, TLS_CTX *ctx);"
)

vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "int tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client)\n{"
    "size_t tls_ctx_sizeof(void)\n{\n\treturn sizeof(TLS_CTX);\n}\n\nint tls_ctx_init(TLS_CTX *ctx, int protocol, int is_client)\n{"
)

vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "int tls_init(TLS_CONNECT *conn, TLS_CTX *ctx)\n{"
    "size_t tls_connect_sizeof(void)\n{\n\treturn sizeof(TLS_CONNECT);\n}\n\nint tls_init(TLS_CONNECT *conn, TLS_CTX *ctx)\n{"
)
# --- end original abi-contract.cmake ---

# --- begin original hardening/ubsan-undefined-behavior.cmake (Git blob 9ef3faf05394082618dceb2d811ce7e4e9a84546) ---
# Crypto-owned post-import hardening. Do not edit the frozen 92 imported source
# blobs or change the 40 attested GmSSL 3.2.0#13 original transformations.
# All substitutions fail closed on source drift or ambiguous anchors.

function(crypto_gmssl_harden_once filename original fixed)
  if(NOT EXISTS "${filename}" OR "${original}" STREQUAL "")
    message(FATAL_ERROR "Invalid crypto source-hardening input: ${filename}")
  endif()
  set(_expected 1)
  if(ARGC EQUAL 4)
    set(_expected "${ARGV3}")
  elseif(NOT ARGC EQUAL 3)
    message(FATAL_ERROR "Invalid source hardening call arity")
  endif()
  file(READ "${filename}" _before)
  string(LENGTH "${original}" _length)
  set(_remainder "${_before}")
  set(_found 0)
  while(TRUE)
    string(FIND "${_remainder}" "${original}" _at)
    if(_at EQUAL -1)
      break()
    endif()
    math(EXPR _found "${_found} + 1")
    math(EXPR _after_offset "${_at} + ${_length}")
    string(SUBSTRING "${_remainder}" ${_after_offset} -1 _remainder)
  endwhile()
  if(NOT _found EQUAL _expected)
    message(FATAL_ERROR
      "Crypto hardening expected ${_expected} source anchors but found ${_found}: ${filename}")
  endif()
  string(REPLACE "${original}" "${fixed}" _after "${_before}")
  if("${_after}" STREQUAL "${_before}")
    message(FATAL_ERROR "Crypto hardening produced no source edit: ${filename}")
  endif()
  file(WRITE "${filename}" "${_after}")
endfunction()

# bn_add() returns an int carry bit. Signed (c & 1) << 31 has undefined
# behavior when c == 1. Cast the bit to a uint32_t before shifting to the
# high bit of the unsigned limb; the mathematical field operation is unchanged.
crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/secp256r1.c"
  [==[r[7] = (r[7] >> 1) | ((c & 1) << 31);]==]
  [==[r[7] = (r[7] >> 1) | ((uint32_t)(c & 1) << 31);]==])

crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/secp384r1.c"
  [==[r[11] = (r[11] >> 1) | ((c & 1) << 31);]==]
  [==[r[11] = (r[11] >> 1) | ((uint32_t)(c & 1) << 31);]==])

# TLS 1.2 ServerHello may contain a zero-length legacy session ID. The
# decoder's data pointer may legitimately be NULL for the empty vector.
# Never pass NULL to memcpy (even with size 0); also reject oversized IDs
# before copying to conn->session_id[32].
crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/tls12.c"
  [==[	// session_id
	memcpy(conn->session_id, session_id, session_id_len);
	conn->session_id_len = session_id_len;]==]
  [==[	// session_id
	if (session_id_len > sizeof(conn->session_id)
		|| (session_id_len && !session_id)) {
		error_print();
		tls_send_alert(conn, TLS_alert_decode_error);
		return -1;
	}
	if (session_id_len) {
		memcpy(conn->session_id, session_id, session_id_len);
	}
	conn->session_id_len = session_id_len;]==])

# TLS 1.3 ServerHello is also allowed to return an empty legacy
# session_id_echo. The decoder can represent the zero-length vector as
# NULL; memcmp(NULL, ..., 0) is undefined. Reject mismatched lengths or
# invalid nonempty pointers, and compare bytes only for a nonempty echo.
crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/tls13.c"
  [==[	// legacy_session_id_echo
	if (legacy_session_id_echo_len != conn->session_id_len
		|| memcmp(legacy_session_id_echo, conn->session_id, conn->session_id_len) != 0) {]==]
  [==[	// legacy_session_id_echo
	if (conn->session_id_len > sizeof(conn->session_id)
		|| legacy_session_id_echo_len != conn->session_id_len
		|| (conn->session_id_len
			&& (!legacy_session_id_echo
				|| memcmp(legacy_session_id_echo, conn->session_id, conn->session_id_len) != 0))) {]==]
  2)

message(STATUS "Applied 5 Crypto-owned post-import UB hardening edits")
# --- end original hardening/ubsan-undefined-behavior.cmake ---

# --- begin original hardening/tls13-hrr-compat-ccs.cmake (Git blob e21404c4c285590f1140707e9caab6f255344471) ---
# Crypto-owned POST-IMPORT protocol fix, separate from 40 original
# adaptations and five existing Crypto undefined-behavior hardenings.
# RFC 8446 section 5.1 / appendix D.4 allows a single strict dummy
# ChangeCipherSpec between HRR and the second ClientHello.
#
# The native opaque Crypto C11 facade enables accept_change_cipher_spec
# ONLY for its TLS1.3 server profile. No public C11 ABI or GmSSL
# private function table is exposed or replaced.
#
# A malformed / duplicate CCS or non-handshake record FAILS CLOSED,
# never skipped, and only one validated 0x01 byte can be discarded.
# The cached first ClientHello, transcript hashes and Finished checks
# remain completely unchanged.
crypto_gmssl_harden_once(
  "${SOURCE_PATH}/include/gmssl/tls.h"
  [==[	// HelloRetryRequest
	int hello_retry_request;]==]
  [==[	// HelloRetryRequest
	int hello_retry_request;
	// Private per-session bounded TLS1.3 compatibility CCS after HRR.
	unsigned int crypto_hrr_ccs_seen;]==])

crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/tls13.c"
  [==[	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv ClientHello again\n");]==]
  [==[	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	// OpenSSL3's middlebox compatibility mode may send exactly one
	// RFC8446 dummy CCS (type 20, legacy 0x0303, length 1, byte 0x01)
	// before ClientHello2 after a legitimate HelloRetryRequest.
	// Consume only when explicitly configured in the private TLS_CTX.
	// Returning AGAIN allows the existing state machine to receive and
	// *fully authenticate* ClientHello2 on its next bounded drive.
	if (tls_record_type(conn->record) == TLS_record_change_cipher_spec) {
		if (!conn->ctx->accept_change_cipher_spec
			|| conn->crypto_hrr_ccs_seen != 0u) {
			tls13_send_alert(conn, TLS_alert_unexpected_message);
			return -1;
		}
		if (conn->recordlen != TLS_RECORD_HEADER_SIZE + 1u
			|| tls_record_protocol(conn->record) != TLS_protocol_tls12
			|| tls_record_get_change_cipher_spec(conn->record) != 1) {
			tls13_send_alert(conn, TLS_alert_decode_error);
			return -1;
		}
		conn->crypto_hrr_ccs_seen = 1u;
		tls_clean_record(conn);
		return TLS_ERROR_RECV_AGAIN;
	}
	if (tls_record_type(conn->record) != TLS_record_handshake) {
		tls13_send_alert(conn, TLS_alert_unexpected_message);
		return -1;
	}
	if(conn->verbose) tls_trace("recv ClientHello again\n");]==])
# --- end original hardening/tls13-hrr-compat-ccs.cmake ---

