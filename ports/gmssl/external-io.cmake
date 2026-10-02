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
