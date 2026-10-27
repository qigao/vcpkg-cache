# GmSSL port source transformations (phase 1/4): primitives and core TLS.
# Order-preserving consolidation: original source-bearing C/H inputs are now pinned in qigao/crypto.
# GmSSL source and ABI behavior must remain unchanged.

# --- begin original legacy-md5.cmake (Git blob 109b4cafda3afbe60956fe560c5f1d96c9a22be3) ---
# Add the bounded legacy MD5 primitive required by protocol-compatibility
# consumers such as TURN and S3 SSE-C. This remains part of the private GmSSL
# provider package and intentionally does not recreate any OpenSSL compatibility
# surface.

file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/include/gmssl/md5.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/src/md5.c"
     DESTINATION "${SOURCE_PATH}/src")

vcpkg_replace_string(
    "${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c"
    "src/debug.c\nsrc/md5.c"
)
# --- end original legacy-md5.cmake ---

# --- begin original legacy-des.cmake (Git blob 77807798caeb0116b9afde4dc9a08ee8650b4e19) ---
# Add the bounded legacy DES-CBC primitive required by protocol-compatibility
# consumers such as SNMPv3 USM. This remains part of the private GmSSL provider
# package and intentionally does not recreate any OpenSSL compatibility surface.

file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/include/gmssl/des.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/src/des.c"
     DESTINATION "${SOURCE_PATH}/src")

vcpkg_replace_string(
    "${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c"
    "src/debug.c\nsrc/des.c"
)
# --- end original legacy-des.cmake ---

# --- begin original key-wrap.cmake (Git blob a8ff5fa8579a9a7df7113099d741469896a20a42) ---
# Native RFC 3394 provider API, composed from GmSSL AES and secure memory APIs.
file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/include/gmssl/aes_key_wrap.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
file(COPY "${GMSSL_CRYPTO_EXTENSIONS_SOURCE}/src/aes_key_wrap.c"
     DESTINATION "${SOURCE_PATH}/src")
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c" "src/debug.c\nsrc/aes_key_wrap.c")
# --- end original key-wrap.cmake ---

# --- begin original portability.cmake (Git blob c4bc8649edb471fe7075f073fa4f55dddfa9fd2b) ---
# Normalize public Windows preprocessor guards for ordinary MSVC consumers.
# MSVC guarantees _WIN32; WIN32 is not a language/toolchain guarantee.

foreach(_gmssl_public_header IN ITEMS
        "${SOURCE_PATH}/include/gmssl/socket.h"
        "${SOURCE_PATH}/include/gmssl/dylib.h")
    vcpkg_replace_string(
        "${_gmssl_public_header}"
        "#ifdef WIN32"
        "#if defined(_WIN32) || defined(WIN32)"
    )
endforeach()

unset(_gmssl_public_header)

# Android API 24 does not export getentropy(). Preserve GmSSL's bounded
# 256-byte rand_bytes() contract with a fail-closed /dev/urandom read loop.
set(_gmssl_rand_unix_c "${SOURCE_PATH}/src/rand_unix.c")
vcpkg_replace_string(
    "${_gmssl_rand_unix_c}"
    "#include <unistd.h> // in Linux"
    "#include <unistd.h> // in Linux\n#ifdef __ANDROID__\n#include <errno.h>\n#include <fcntl.h>\n#endif"
)
vcpkg_replace_string(
    "${_gmssl_rand_unix_c}"
[==[
	if (getentropy(buf, len) != 0) {
		error_print();
		return -1;
	}
]==]
[==[
#ifdef __ANDROID__
	{
		int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
		size_t offset = 0;
		if (fd < 0) {
			error_print();
			return -1;
		}
		while (offset < len) {
			ssize_t n = read(fd, buf + offset, len - offset);
			if (n > 0) {
				offset += (size_t)n;
				continue;
			}
			if (n < 0 && errno == EINTR) {
				continue;
			}
			(void)close(fd);
			error_print();
			return -1;
		}
		if (close(fd) != 0) {
			error_print();
			return -1;
		}
	}
#else
	if (getentropy(buf, len) != 0) {
		error_print();
		return -1;
	}
#endif
]==]
)
unset(_gmssl_rand_unix_c)
# --- end original portability.cmake ---

# --- begin original external-io.cmake (Git blob c5975318994576c85c9b8f131bb82df52fdc3077) ---
# Apply the Salts-required external-I/O contract to upstream GmSSL 3.2.0.
# Keep this as a narrow source adaptation until the API is available upstream.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")
set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")

# Add a copied per-connection callback contract and keep the existing socket
# field for upstream tools/tests.
vcpkg_replace_string(
    "${_gmssl_tls_h}"
    "typedef struct {\n\tint is_client; // 这个在CTX中应该是有的\n\n\ttls_socket_t sock;\n\n\tTLS_CTX *ctx;"
    "typedef tls_ret_t (*tls_io_send_fn)(void *user, const void *buf, size_t len, int flags);\ntypedef tls_ret_t (*tls_io_recv_fn)(void *user, void *buf, size_t len, int flags);\ntypedef struct {\n\tvoid *user;\n\ttls_io_send_fn send;\n\ttls_io_recv_fn recv;\n} TLS_IO;\n\ntypedef struct {\n\tint is_client; // 这个在CTX中应该是有的\n\n\ttls_socket_t sock;\n\tTLS_IO io;\n\n\tTLS_CTX *ctx;"
)

vcpkg_replace_string(
    "${_gmssl_tls_h}"
    "int tls_set_socket(TLS_CONNECT *conn, tls_socket_t sock);\n\n\nint tls_do_handshake(TLS_CONNECT *conn);"
    "int tls_set_socket(TLS_CONNECT *conn, tls_socket_t sock);\nint tls_set_io(TLS_CONNECT *conn, const TLS_IO *io);\ntls_ret_t tls_io_send(TLS_CONNECT *conn, const void *buf, size_t len, int flags);\ntls_ret_t tls_io_recv(TLS_CONNECT *conn, void *buf, size_t len, int flags);\n\n\nint tls_do_handshake(TLS_CONNECT *conn);"
)

# Redirect only connection-owned record I/O. The standalone tls_record_send()
# socket helper remains unchanged for upstream callers.
vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "tls_socket_send(conn->sock,"
    "tls_io_send(conn,"
)
vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "tls_socket_recv(conn->sock,"
    "tls_io_recv(conn,"
)
vcpkg_replace_string(
    "${_gmssl_tls13_c}"
    "tls_socket_send(conn->sock,"
    "tls_io_send(conn,"
)
vcpkg_replace_string(
    "${_gmssl_tls13_c}"
    "tls_socket_recv(conn->sock,"
    "tls_io_recv(conn,"
)

# Fatal/warning alerts must also respect external-I/O ownership rather than
# bypassing it through tls_record_send(sock).
vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "tls_record_send(record, sizeof(record), conn->sock)"
    "tls_record_send_io(record, recordlen, conn)"
)

# Extend tls_set_socket() with mutually-exclusive callback I/O and normalized
# error translation. Existing state-machine error handling remains unchanged:
# callbacks are translated to the same errno/WSA error categories used by the
# socket path.
vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "int tls_set_socket(TLS_CONNECT *conn, tls_socket_t sock)\n{\n\tif (!conn || !tls_socket_is_valid(sock)) {\n\t\terror_print();\n\t\treturn -1;\n\t}\n\tconn->sock = sock;\n\treturn 1;\n}\n"
    "int tls_set_socket(TLS_CONNECT *conn, tls_socket_t sock)\n{\n\tif (!conn || !tls_socket_is_valid(sock) || conn->io.send || conn->io.recv) {\n\t\terror_print();\n\t\treturn -1;\n\t}\n\tconn->sock = sock;\n\treturn 1;\n}\n\nint tls_set_io(TLS_CONNECT *conn, const TLS_IO *io)\n{\n\tif (!conn || !io || !io->send || !io->recv) {\n\t\terror_print();\n\t\treturn -1;\n\t}\n\tconn->io = *io;\n\tconn->sock = tls_socket_invalid();\n\treturn 1;\n}\n\nstatic tls_ret_t tls_io_translate_result(tls_ret_t ret)\n{\n\tif (ret >= 0) {\n\t\treturn ret;\n\t}\n\tif (ret == TLS_ERROR_TCP_CLOSED) {\n\t\treturn 0;\n\t}\n#ifdef WIN32\n\tif (ret == TLS_ERROR_RECV_AGAIN || ret == TLS_ERROR_SEND_AGAIN) {\n\t\tWSASetLastError(WSAEWOULDBLOCK);\n\t} else {\n\t\tWSASetLastError(WSAEINVAL);\n\t}\n#else\n\terrno = (ret == TLS_ERROR_RECV_AGAIN || ret == TLS_ERROR_SEND_AGAIN) ? EAGAIN : EIO;\n#endif\n\treturn -1;\n}\n\ntls_ret_t tls_io_send(TLS_CONNECT *conn, const void *buf, size_t len, int flags)\n{\n\tif (!conn || !buf || !len) {\n\t\treturn TLS_ERROR_SYSCALL;\n\t}\n\tif (conn->io.send) {\n\t\treturn tls_io_translate_result(conn->io.send(conn->io.user, buf, len, flags));\n\t}\n\treturn tls_socket_send(conn->sock, buf, len, flags);\n}\n\ntls_ret_t tls_io_recv(TLS_CONNECT *conn, void *buf, size_t len, int flags)\n{\n\tif (!conn || !buf || !len) {\n\t\treturn TLS_ERROR_SYSCALL;\n\t}\n\tif (conn->io.recv) {\n\t\treturn tls_io_translate_result(conn->io.recv(conn->io.user, buf, len, flags));\n\t}\n\treturn tls_socket_recv(conn->sock, buf, len, flags);\n}\n"
)

# Alert records use a connection-aware nonblocking sender. The legacy
# tls_record_send(record, sock) helper remains available for socket callers.
vcpkg_replace_string(
    "${_gmssl_tls_c}"
    "// modify: conn->record_offset\nint tls_send_record(TLS_CONNECT *conn)"
    "static int tls_record_send_io(const uint8_t *record, size_t recordlen, TLS_CONNECT *conn)\n{\n\ttls_ret_t n;\n\tif (!record || !conn || recordlen < TLS_RECORD_HEADER_SIZE ||\n\t\ttls_record_length(record) != recordlen) {\n\t\terror_print();\n\t\treturn -1;\n\t}\n\twhile (recordlen) {\n\t\tn = tls_io_send(conn, record, recordlen, 0);\n\t\tif (n > 0) {\n\t\t\trecord += n;\n\t\t\trecordlen -= (size_t)n;\n\t\t} else if (n == 0) {\n\t\t\treturn TLS_ERROR_TCP_CLOSED;\n\t\t} else {\n\t\t\tint err = tls_socket_get_error();\n\t\t\ttls_socket_err_t type = tls_socket_get_error_type(err, 0);\n\t\t\tif (type == TLS_SOCKET_ERR_WANT_WRITE) {\n\t\t\t\treturn TLS_ERROR_SEND_AGAIN;\n\t\t\t} else if (type == TLS_SOCKET_ERR_INTERRUPTED) {\n\t\t\t\tcontinue;\n\t\t\t}\n\t\t\treturn TLS_ERROR_SYSCALL;\n\t\t}\n\t}\n\treturn 1;\n}\n\n// modify: conn->record_offset\nint tls_send_record(TLS_CONNECT *conn)"
)
# --- end original external-io.cmake ---

# --- begin original standard-tls.cmake (Git blob 6aa4e108fca2adad236b0aa5455885a63853fb03) ---
# Standard TLS compatibility adaptations required by Salts/CNet.
# Keep each adaptation narrow and independently testable.

set(_gmssl_tls12_c "${SOURCE_PATH}/src/tls12.c")

function(gmssl_replace_once file_path search_text replacement_text)
    file(READ "${file_path}" _gmssl_replace_content)
    string(FIND "${_gmssl_replace_content}" "${search_text}" _gmssl_replace_offset)
    if(_gmssl_replace_offset EQUAL -1)
        message(FATAL_ERROR "GmSSL standard-TLS adaptation anchor not found in ${file_path}")
    endif()
    string(LENGTH "${search_text}" _gmssl_replace_length)
    string(SUBSTRING "${_gmssl_replace_content}" 0 ${_gmssl_replace_offset} _gmssl_replace_prefix)
    math(EXPR _gmssl_replace_suffix_offset "${_gmssl_replace_offset} + ${_gmssl_replace_length}")
    string(SUBSTRING "${_gmssl_replace_content}" ${_gmssl_replace_suffix_offset} -1 _gmssl_replace_suffix)
    file(WRITE "${file_path}" "${_gmssl_replace_prefix}${replacement_text}${_gmssl_replace_suffix}")
endfunction()

# TLS 1.2 client: advertise configured ALPN protocols in ClientHello.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		// renegotiation_info
		if (conn->ctx->renegotiation_info) {
]==]
[==[
		// application_layer_protocol_negotiation
		if (conn->ctx->alpn_protocols_cnt) {
			if (tls_application_layer_protocol_negotiation_ext_to_bytes(
				conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt,
				&pexts, &extslen) != 1) {
				error_print();
				return -1;
			}
		}

		// renegotiation_info
		if (conn->ctx->renegotiation_info) {
]==]
)

# TLS 1.2 client: retain the server-selected ALPN protocol from ServerHello.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	int trusted_ca_keys = 0;
	int renegotiation_info = 0;
]==]
[==[
	int trusted_ca_keys = 0;
	const uint8_t *application_layer_protocol_negotiation = NULL;
	size_t application_layer_protocol_negotiation_len = 0;
	int renegotiation_info = 0;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		case TLS_extension_ec_point_formats:
			if (ec_point_formats) {
]==]
[==[
		case TLS_extension_application_layer_protocol_negotiation:
			if (!ext_data || application_layer_protocol_negotiation) {
				error_print();
				tls_send_alert(conn, TLS_alert_illegal_parameter);
				return -1;
			}
			application_layer_protocol_negotiation = ext_data;
			application_layer_protocol_negotiation_len = ext_datalen;
			break;
		case TLS_extension_ec_point_formats:
			if (ec_point_formats) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if ((conn->ctx->renegotiation_info || conn->ctx->empty_renegotiation_info_scsv)
]==]
[==[
	if (application_layer_protocol_negotiation) {
		if (!conn->ctx->alpn_protocols_cnt
			|| tls_application_layer_protocol_negotiation_selected_from_bytes(
				&conn->alpn_selected,
				application_layer_protocol_negotiation, application_layer_protocol_negotiation_len,
				conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt) != 1) {
			error_print();
			tls_send_alert(conn, TLS_alert_illegal_parameter);
			return -1;
		}
		conn->application_layer_protocol_negotiation = 1;
	}

	if ((conn->ctx->renegotiation_info || conn->ctx->empty_renegotiation_info_scsv)
]==]
)

# TLS 1.2 server: parse the client's ALPN offer and select one local protocol.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	const uint8_t *renegotiation_info = NULL;
	size_t renegotiation_info_len = 0;
]==]
[==[
	const uint8_t *application_layer_protocol_negotiation = NULL;
	size_t application_layer_protocol_negotiation_len = 0;
	const uint8_t *renegotiation_info = NULL;
	size_t renegotiation_info_len = 0;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		case TLS_extension_renegotiation_info:
			if (renegotiation_info) {
]==]
[==[
		case TLS_extension_application_layer_protocol_negotiation:
			if (!ext_data || application_layer_protocol_negotiation) {
				error_print();
				tls_send_alert(conn, TLS_alert_illegal_parameter);
				return -1;
			}
			application_layer_protocol_negotiation = ext_data;
			application_layer_protocol_negotiation_len = ext_datalen;
			break;
		case TLS_extension_renegotiation_info:
			if (renegotiation_info) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if (server_name) {
		if (tls_server_name_from_bytes(&host_name, &host_name_len, server_name, server_name_len) != 1) {
]==]
[==[
	if (application_layer_protocol_negotiation) {
		if (!conn->ctx->alpn_protocols_cnt) {
			error_print();
			tls_send_alert(conn, TLS_alert_no_application_protocol);
			return -1;
		}
		if ((ret = tls_application_layer_protocol_negotiation_select(
			application_layer_protocol_negotiation, application_layer_protocol_negotiation_len,
			conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt,
			&conn->alpn_selected)) != 1) {
			error_print();
			tls_send_alert(conn, TLS_alert_no_application_protocol);
			return -1;
		}
		conn->application_layer_protocol_negotiation = 1;
	}

	if (server_name) {
		if (tls_server_name_from_bytes(&host_name, &host_name_len, server_name, server_name_len) != 1) {
]==]
)

# TLS 1.2 server: return the selected ALPN protocol in ServerHello.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		// renegotiation_info
		if (conn->secure_renegotiation) {
]==]
[==[
		// application_layer_protocol_negotiation
		if (conn->alpn_selected) {
			if (tls_application_layer_protocol_negotiation_selected_ext_to_bytes(
				conn->alpn_selected, &pexts, &extslen) != 1) {
				error_print();
				return -1;
			}
		}

		// renegotiation_info
		if (conn->secure_renegotiation) {
]==]
)

unset(_gmssl_tls12_c)

# TLS 1.3 client: CertificateRequest must ignore unknown extensions for
# forward compatibility. Keep all known extension validation strict.
set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
		case TLS_extension_signed_certificate_timestamp:
			if (signed_certificate_timestamp) {
				error_print();
				tls13_send_alert(conn, TLS_alert_illegal_parameter);
				return -1;
			}
			signed_certificate_timestamp = 1;
			break;

		default:
			error_print();
			tls13_send_alert(conn, TLS_alert_illegal_parameter);
			return -1;
		}
]==]
[==[
		case TLS_extension_signed_certificate_timestamp:
			if (signed_certificate_timestamp) {
				error_print();
				tls13_send_alert(conn, TLS_alert_illegal_parameter);
				return -1;
			}
			signed_certificate_timestamp = 1;
			break;

		default:
			/* RFC 8446 extension processing requires unknown extensions to be
			 * ignored. They do not participate in client-certificate selection. */
			break;
		}
]==]
)
file(READ "${_gmssl_tls13_c}" _gmssl_tls13_after)
string(FIND "${_gmssl_tls13_after}"
    "RFC 8446 extension processing requires unknown extensions to be"
    _gmssl_tls13_unknown_ext_offset)
if(_gmssl_tls13_unknown_ext_offset EQUAL -1)
    message(FATAL_ERROR "GmSSL TLS 1.3 CertificateRequest unknown-extension contract missing")
endif()
unset(_gmssl_tls13_unknown_ext_offset)
unset(_gmssl_tls13_after)
unset(_gmssl_tls13_c)
# --- end original standard-tls.cmake ---

# --- begin original tls13-certificate-selection.cmake (Git blob cecb35024d2a51a40a7db2afd09d4f09a2ae3588) ---
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
# --- end original tls13-certificate-selection.cmake ---

# --- begin original alpn-capacity.cmake (Git blob 2a998d4e70f4d504951f121ea131510a87d39e10) ---
# Borrowed ALPN list storage bounded by the protocol's uint16 wire length.
# The embedding context owns the pointer list and strings for the TLS_CTX lifetime.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")
set(_gmssl_tls_alpn_c "${SOURCE_PATH}/src/tls_alpn.c")

vcpkg_replace_string(
    "${_gmssl_tls_h}"
    "	char *alpn_protocols[4];"
    "	char **alpn_protocols;"
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
int tls_ctx_set_application_layer_protocol_negotiation(TLS_CTX *ctx,
	char *protocols[], size_t protocols_cnt)
{
	size_t i;

	if (!ctx || !protocols || !protocols_cnt) {
		error_print();
		return -1;
	}
	if (protocols_cnt > sizeof(ctx->alpn_protocols)/sizeof(ctx->alpn_protocols[0])) {
		error_print();
		return -1;
	}
	for (i = 0; i < protocols_cnt; i++) {
		size_t protocol_len;

		if (!protocols[i]) {
			error_print();
			return -1;
		}
		protocol_len = strlen(protocols[i]);
		if (protocol_len < 1 || protocol_len > 255) {
			error_print();
			return -1;
		}
		ctx->alpn_protocols[i] = protocols[i];
	}
	ctx->alpn_protocols_cnt = protocols_cnt;
	ctx->application_layer_protocol_negotiation = 1;

	return 1;
}
]==]
[==[
int tls_ctx_set_application_layer_protocol_negotiation(TLS_CTX *ctx,
	char *protocols[], size_t protocols_cnt)
{
	enum { TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE = 65535 };
	size_t i;
	size_t wire_len = 0;

	if (!ctx || !protocols || !protocols_cnt) {
		error_print();
		return -1;
	}
	for (i = 0; i < protocols_cnt; i++) {
		size_t protocol_len;

		if (!protocols[i]) {
			error_print();
			return -1;
		}
		protocol_len = strlen(protocols[i]);
		if (protocol_len < 1 || protocol_len > 255
			|| wire_len > TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE - 1 - protocol_len) {
			error_print();
			return -1;
		}
		wire_len += 1 + protocol_len;
	}
	ctx->alpn_protocols = protocols;
	ctx->alpn_protocols_cnt = protocols_cnt;
	ctx->application_layer_protocol_negotiation = 1;

	return 1;
}
]==]
)

# Keep tls_ctx_check() aligned with the borrowed-list setter. Revalidate the
# same protocol wire bound; never use sizeof(pointer) as a count limit.
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	if (ctx->application_layer_protocol_negotiation && !ctx->alpn_protocols_cnt) {
		error_print();
		return -1;
	}
	if (!ctx->application_layer_protocol_negotiation && ctx->alpn_protocols_cnt) {
		error_print();
		return -1;
	}
	if (ctx->alpn_protocols_cnt > sizeof(ctx->alpn_protocols)/sizeof(ctx->alpn_protocols[0])) {
		error_print();
		return -1;
	}
	for (i = 0; i < ctx->alpn_protocols_cnt; i++) {
		size_t protocol_len;

		if (!ctx->alpn_protocols[i]) {
			error_print();
			return -1;
		}
		protocol_len = strlen(ctx->alpn_protocols[i]);
		if (protocol_len < 1 || protocol_len > 255) {
			error_print();
			return -1;
		}
	}
]==]
[==[
	if (ctx->application_layer_protocol_negotiation
		&& (!ctx->alpn_protocols || !ctx->alpn_protocols_cnt)) {
		error_print();
		return -1;
	}
	if (!ctx->application_layer_protocol_negotiation
		&& (ctx->alpn_protocols || ctx->alpn_protocols_cnt)) {
		error_print();
		return -1;
	}
	if (ctx->alpn_protocols_cnt) {
		enum { TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE = 65535 };
		size_t wire_len = 0;
		for (i = 0; i < ctx->alpn_protocols_cnt; i++) {
			size_t protocol_len;
			if (!ctx->alpn_protocols[i]) {
				error_print();
				return -1;
			}
			protocol_len = strlen(ctx->alpn_protocols[i]);
			if (protocol_len < 1 || protocol_len > 255
				|| wire_len > TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE - 1 - protocol_len) {
				error_print();
				return -1;
			}
			wire_len += 1 + protocol_len;
		}
	}
]==]
)


# The serializer must enforce the protocol wire bound, not a TLS_CTX storage count.
gmssl_replace_once(
    "${_gmssl_tls_alpn_c}"
[==[
#define tls_application_layer_protocol_negotiation_max_count() \
	(sizeof(((TLS_CTX *)0)->alpn_protocols) \
		/ sizeof(((TLS_CTX *)0)->alpn_protocols[0]))


]==]
[==[
#define TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE 65535
#define tls_application_layer_protocol_negotiation_max_count() \
	(TLS_ALPN_PROTOCOL_NAME_LIST_MAX_SIZE / 2u)


]==]
)

gmssl_replace_once(
    "${_gmssl_tls_alpn_c}"
[==[
	if (!protocols || !protocols_cnt
		|| protocols_cnt > tls_application_layer_protocol_negotiation_max_count()
		|| !outlen) {
]==]
[==[
	if (!protocols || !protocols_cnt || !outlen) {
]==]
)


# tls_ctx_check() must validate the same borrowed-list wire bound as the setter.
vcpkg_replace_string(
    "${_gmssl_tls_c}"
[==[
	if (ctx->alpn_protocols_cnt > sizeof(ctx->alpn_protocols)/sizeof(ctx->alpn_protocols[0])) {
		error_print();
		return -1;
	}
]==]
[==[
	size_t alpn_wire_len = 0;
]==]
)

vcpkg_replace_string(
    "${_gmssl_tls_c}"
[==[
		protocol_len = strlen(ctx->alpn_protocols[i]);
		if (protocol_len < 1 || protocol_len > 255) {
			error_print();
			return -1;
		}
]==]
[==[
		protocol_len = strlen(ctx->alpn_protocols[i]);
		if (protocol_len < 1 || protocol_len > 255
			|| alpn_wire_len > 65535 - 1 - protocol_len) {
			error_print();
			return -1;
		}
		alpn_wire_len += 1 + protocol_len;
]==]
)


# CNet's canonical ALPN contract is server-preferred. Upstream scans the peer
# list first, which makes client order win. Scan the complete peer list once
# for each local protocol instead, preserving local/server preference.
gmssl_replace_once(
    "${_gmssl_tls_alpn_c}"
[==[
	while (protocol_name_list_len) {
		const uint8_t *peer_protocol;
		size_t peer_protocol_len;

		if (tls_uint8array_from_bytes(&peer_protocol, &peer_protocol_len,
				&protocol_name_list, &protocol_name_list_len) != 1) {
			error_print();
			return -1;
		}
		if (!peer_protocol || !peer_protocol_len) {
			error_print();
			return -1;
		}

		for (i = 0; i < local_protocols_cnt; i++) {
			if (tls_application_layer_protocol_negotiation_match(
					peer_protocol, peer_protocol_len,
					local_protocols[i]) == 1) {
				*selected = local_protocols[i];
				return 1;
			}
		}
	}
]==]
[==[
	for (i = 0; i < local_protocols_cnt; i++) {
		const uint8_t *peer_list = protocol_name_list;
		size_t peer_list_len = protocol_name_list_len;

		while (peer_list_len) {
			const uint8_t *peer_protocol;
			size_t peer_protocol_len;

			if (tls_uint8array_from_bytes(&peer_protocol, &peer_protocol_len,
					&peer_list, &peer_list_len) != 1) {
				error_print();
				return -1;
			}
			if (!peer_protocol || !peer_protocol_len) {
				error_print();
				return -1;
			}
			if (tls_application_layer_protocol_negotiation_match(
					peer_protocol, peer_protocol_len,
					local_protocols[i]) == 1) {
				*selected = local_protocols[i];
				return 1;
			}
		}
	}
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
unset(_gmssl_tls_alpn_c)
# --- end original alpn-capacity.cmake ---

# --- begin original trust-anchors.cmake (Git blob 20d0d93e6697d565e04d10dd3fe04ea934ecc8cb) ---
# Trust-anchor APIs required by Salts/CNet platform trust-store integration.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_cert_c "${SOURCE_PATH}/src/tls_cert.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
]==]
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
int tls_ctx_set_ca_certificates_der(TLS_CTX *ctx,
	const uint8_t *cacerts, size_t cacertslen, int depth);
]==]
)

# Client trust bundles can contain hundreds of roots. ca_names/trusted_authorities
# are CertificateRequest/trusted_ca_keys presentation data and must not bound
# the client verification store to the fixed 512-byte name buffer.
gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
	// 在读取CA证书的时候，提取了证书的名字
	if (tls_authorities_from_certs(ctx->ca_names, &ctx->ca_names_len, sizeof(ctx->ca_names),
		ctx->cacerts, ctx->cacertslen) != 1) {
		error_print();
		return -1;
	}
	if (tls_trusted_authorities_from_ca_names(ctx->trusted_authorities, &ctx->trusted_authorities_len,
		sizeof(ctx->trusted_authorities), ctx->ca_names, ctx->ca_names_len) != 1) {
		error_print();
		return -1;
	}

	ctx->verify_depth = depth;
	return 1;
}
]==]
[==[
	// Server-side CertificateRequest/trusted_ca_keys may expose authority names.
	// Client-side verification needs the full trust store, not a 512-byte name list.
	if (!ctx->is_client) {
		if (tls_authorities_from_certs(ctx->ca_names, &ctx->ca_names_len, sizeof(ctx->ca_names),
			ctx->cacerts, ctx->cacertslen) != 1) {
			error_print();
			return -1;
		}
		if (tls_trusted_authorities_from_ca_names(
			ctx->trusted_authorities, &ctx->trusted_authorities_len,
			sizeof(ctx->trusted_authorities), ctx->ca_names, ctx->ca_names_len) != 1) {
			error_print();
			return -1;
		}
	}

	ctx->verify_depth = depth;
	return 1;
}

int tls_ctx_set_ca_certificates_der(TLS_CTX *ctx,
	const uint8_t *cacerts, size_t cacertslen, int depth)
{
	uint8_t *copy = NULL;
	size_t certs_cnt = 0;

	if (!ctx || !cacerts || !cacertslen) {
		error_print();
		return -1;
	}
	if (depth < 0 || depth > TLS_MAX_VERIFY_DEPTH
		|| !tls_protocol_name(ctx->protocol)
		|| ctx->cacerts) {
		error_print();
		return -1;
	}
	if (x509_certs_get_count(cacerts, cacertslen, &certs_cnt) != 1
		|| certs_cnt == 0) {
		error_print();
		return -1;
	}
	copy = (uint8_t *)malloc(cacertslen);
	if (!copy) {
		error_print();
		return -1;
	}
	memcpy(copy, cacerts, cacertslen);
	ctx->cacerts = copy;
	ctx->cacertslen = cacertslen;

	if (!ctx->is_client) {
		if (tls_authorities_from_certs(ctx->ca_names, &ctx->ca_names_len,
				sizeof(ctx->ca_names), ctx->cacerts, ctx->cacertslen) != 1
			|| tls_trusted_authorities_from_ca_names(
				ctx->trusted_authorities, &ctx->trusted_authorities_len,
				sizeof(ctx->trusted_authorities),
				ctx->ca_names, ctx->ca_names_len) != 1) {
			free(ctx->cacerts);
			ctx->cacerts = NULL;
			ctx->cacertslen = 0;
			ctx->ca_names_len = 0;
			ctx->trusted_authorities_len = 0;
			error_print();
			return -1;
		}
	}
	ctx->verify_depth = depth;
	return 1;
}
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_cert_c)
# --- end original trust-anchors.cmake ---

# --- begin original external-trust.cmake (Git blob 7c49465ffad61f6a2bd3a3851f2ea3f0fa1dc8fc) ---
# External platform-trust seam for consumers that cannot enumerate native roots
# (notably iOS Security.framework). This skips only GmSSL's trust-anchor path
# verification; certificate matching, hostname checks and CertificateVerify stay
# inside GmSSL.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_cert_c "${SOURCE_PATH}/src/tls_cert.c")
set(_gmssl_tls12_c "${SOURCE_PATH}/src/tls12.c")
set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
	uint8_t *cacerts;
	size_t cacertslen;
	int verify_depth;
]==]
[==[
	uint8_t *cacerts;
	size_t cacertslen;
	int verify_depth;
	int external_trust;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
]==]
[==[
int tls_ctx_set_ca_certificates(TLS_CTX *ctx, const char *cacertsfile, int depth);
int tls_ctx_enable_external_trust(TLS_CTX *ctx, int enable);
]==]
)

# File-backed CA trust and external trust are mutually exclusive.
gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
	if (ctx->cacerts) {
]==]
[==[
	if (ctx->cacerts || ctx->external_trust) {
]==]
)

# The DER trust-store adaptation is injected by trust-anchors.cmake earlier.
gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
		|| !tls_protocol_name(ctx->protocol)
		|| ctx->cacerts) {
]==]
[==[
		|| !tls_protocol_name(ctx->protocol)
		|| ctx->cacerts || ctx->external_trust) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_cert_c}"
[==[
int tls_authorities_from_certs(uint8_t *names, size_t *nameslen, size_t maxlen, const uint8_t *certs, size_t certslen)
]==]
[==[
int tls_ctx_enable_external_trust(TLS_CTX *ctx, int enable)
{
	if (!ctx || !ctx->is_client || (enable != 0 && enable != 1)) {
		error_print();
		return -1;
	}
	if (enable && ctx->cacerts) {
		error_print();
		return -1;
	}
	ctx->external_trust = enable;
	return 1;
}

int tls_authorities_from_certs(uint8_t *names, size_t *nameslen, size_t maxlen, const uint8_t *certs, size_t certslen)
]==]
)

# TLS 1.2 already makes chain verification conditional on CA presence. External
# trust must explicitly override that path while retaining tls_cert_chain_match.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		conn->ctx->cacertslen ? 1 : 0,
		conn->peer_cert_chain, conn->peer_cert_chain_len,
]==]
[==[
		conn->ctx->external_trust ? 0 : (conn->ctx->cacertslen ? 1 : 0),
		conn->peer_cert_chain, conn->peer_cert_chain_len,
]==]
)

# TLS 1.3 hard-codes verify_chain=1 upstream. Keep that default, but allow the
# explicit client-only external-trust seam to defer only the root/path decision.
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
	ret = tls_cert_chain_verify(
		conn->protocol, X509_cert_chain_server, conn->cipher_suite,
		1,
		conn->peer_cert_chain, conn->peer_cert_chain_len,
]==]
[==[
	ret = tls_cert_chain_verify(
		conn->protocol, X509_cert_chain_server, conn->cipher_suite,
		conn->ctx->external_trust ? 0 : 1,
		conn->peer_cert_chain, conn->peer_cert_chain_len,
]==]
)

# Build-time postconditions keep the seam narrow and fail if upstream shifts.
file(READ "${_gmssl_tls_h}" _gmssl_external_trust_h)
file(READ "${_gmssl_tls12_c}" _gmssl_external_trust_tls12)
file(READ "${_gmssl_tls13_c}" _gmssl_external_trust_tls13)
foreach(_needle
    "int tls_ctx_enable_external_trust(TLS_CTX *ctx, int enable);"
    "int external_trust;")
    string(FIND "${_gmssl_external_trust_h}" "${_needle}" _offset)
    if(_offset EQUAL -1)
        message(FATAL_ERROR "GmSSL external-trust header contract missing: ${_needle}")
    endif()
endforeach()
string(FIND "${_gmssl_external_trust_tls12}"
    "conn->ctx->external_trust ? 0 : (conn->ctx->cacertslen ? 1 : 0)"
    _gmssl_external_trust_tls12_offset)
if(_gmssl_external_trust_tls12_offset EQUAL -1)
    message(FATAL_ERROR "GmSSL TLS 1.2 external-trust contract missing")
endif()
string(FIND "${_gmssl_external_trust_tls13}"
    "conn->ctx->external_trust ? 0 : 1"
    _gmssl_external_trust_tls13_offset)
if(_gmssl_external_trust_tls13_offset EQUAL -1)
    message(FATAL_ERROR "GmSSL TLS 1.3 external-trust contract missing")
endif()

unset(_gmssl_external_trust_tls13_offset)
unset(_gmssl_external_trust_tls12_offset)
unset(_gmssl_external_trust_tls13)
unset(_gmssl_external_trust_tls12)
unset(_gmssl_external_trust_h)
unset(_gmssl_tls13_c)
unset(_gmssl_tls12_c)
unset(_gmssl_tls_cert_c)
unset(_gmssl_tls_h)
# --- end original external-trust.cmake ---

# --- begin original tls-lifecycle.cmake (Git blob 349394d7130d41463bf510031fc26625238355be) ---
# Release heap-backed TLS client verification transcript state before the
# connection object is securely cleared.

set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
void tls_cleanup(TLS_CONNECT *conn)
{
	gmssl_secure_clear(conn, sizeof(TLS_CONNECT));
}
]==]
[==[
void tls_cleanup(TLS_CONNECT *conn)
{
	if (!conn) {
		return;
	}
	tls_client_verify_cleanup(&conn->client_verify_ctx);
	gmssl_secure_clear(conn, sizeof(TLS_CONNECT));
}
]==]
)

unset(_gmssl_tls_c)
# --- end original tls-lifecycle.cmake ---

# --- begin original x509-compat.cmake (Git blob a7d48af97954e3d8e5e12979c18e83eb552679fd) ---
# X.509 interoperability fixes required by standard TLS peers.

set(_gmssl_x509_ext_c "${SOURCE_PATH}/src/x509_ext.c")

# RFC 5280 BasicConstraints has cA BOOLEAN DEFAULT FALSE and optional
# pathLenConstraint. Therefore an empty SEQUENCE is the canonical encoding of
# an end-entity CA:FALSE constraint. GmSSL 3.2.0 incorrectly rejects it.
gmssl_replace_once(
    "${_gmssl_x509_ext_c}"
[==[
	if (dlen == 0) {
		error_print();
		return -1;
	}
	if (asn1_boolean_from_der(ca, &d, &dlen) < 0
]==]
[==[
	if (dlen == 0) {
		*ca = 0;
		*path_len_cons = -1;
		return 1;
	}
	if (asn1_boolean_from_der(ca, &d, &dlen) < 0
]==]
)

unset(_gmssl_x509_ext_c)

set(_gmssl_x509_c "${SOURCE_PATH}/src/x509_cer.c")

# RFC 5280 requires the current time to be inside a certificate's validity
# interval, but does not impose GmSSL's local ten-year duration limit. Public
# trust anchors such as ISRG Root X1 legitimately exceed that duration. Keep
# x509_validity_check()'s explicit policy mode for callers that request it and
# let certificate validation opt out with max_secs < 0.
gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (!(not_after - not_before <= (unsigned int)max_secs)) {
		error_print();
		return -1;
	}
]==]
[==[
	if (max_secs >= 0 && (uint64_t)(not_after - not_before) > (uint64_t)max_secs) {
		error_print();
		return -1;
	}
]==]
)

gmssl_replace_once(
    "${_gmssl_x509_c}"
    "x509_validity_check(not_before, not_after, now, X509_VALIDITY_MAX_SECONDS)"
    "x509_validity_check(not_before, not_after, now, -1)"
)

# RFC 5280 serial numbers are positive integers up to 20 octets. There is no
# minimum four-byte requirement; MySQL's generated CA legitimately uses 0x01.
gmssl_replace_once(
    "${_gmssl_x509_c}"
[==[
	if (serial_len < 4) {
		error_print(); // not enough randomness
		return -1; // FIXME: 通过宏设置错误？还是返回一个错误原因，让应用判断？
	}
]==]
[==[
	/* RFC 5280 does not impose a minimum serial-number width. The existing
	 * non-empty check above is sufficient for interoperable certificate parsing. */
]==]
)

file(READ "${_gmssl_x509_c}" _gmssl_x509_after)
string(FIND "${_gmssl_x509_after}" "if (serial_len < 4)" _gmssl_x509_short_serial_guard)
if(NOT _gmssl_x509_short_serial_guard EQUAL -1)
    message(FATAL_ERROR "GmSSL short X.509 serial compatibility adaptation missing")
endif()
string(FIND "${_gmssl_x509_after}"
    "x509_validity_check(not_before, not_after, now, -1)"
    _gmssl_x509_validity_guard)
if(_gmssl_x509_validity_guard EQUAL -1)
    message(FATAL_ERROR "GmSSL X.509 RFC 5280 validity adaptation missing")
endif()
unset(_gmssl_x509_validity_guard)
unset(_gmssl_x509_short_serial_guard)
unset(_gmssl_x509_after)
unset(_gmssl_x509_c)
# --- end original x509-compat.cmake ---

