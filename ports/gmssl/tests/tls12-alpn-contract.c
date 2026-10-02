#include <gmssl/tls.h>

#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <stdio.h>

typedef struct probe_io {
    uint8_t input[TLS_MAX_RECORD_SIZE];
    size_t input_len;
    size_t input_off;
    uint8_t output[TLS_MAX_RECORD_SIZE];
    size_t output_len;
} probe_io;

static tls_ret_t probe_send(void *user, const void *buf, size_t len, int flags)
{
    probe_io *io = (probe_io *)user;
    (void)flags;
    if (!io || !buf || len > sizeof(io->output) - io->output_len) {
        return TLS_ERROR_SYSCALL;
    }
    memcpy(io->output + io->output_len, buf, len);
    io->output_len += len;
    return (tls_ret_t)len;
}

static tls_ret_t probe_recv(void *user, void *buf, size_t len, int flags)
{
    probe_io *io = (probe_io *)user;
    size_t available;
    (void)flags;
    if (!io || !buf) {
        return TLS_ERROR_SYSCALL;
    }
    available = io->input_len - io->input_off;
    if (available == 0) {
        return TLS_ERROR_RECV_AGAIN;
    }
    if (len > available) {
        len = available;
    }
    memcpy(buf, io->input + io->input_off, len);
    io->input_off += len;
    return (tls_ret_t)len;
}

static int configure_tls12_client(TLS_CTX *ctx)
{
    static int cipher_suites[] = {
        TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256
    };
    static int groups[] = {
        TLS_curve_secp256r1
    };
    static int sig_algs[] = {
        TLS_sig_ecdsa_secp256r1_sha256
    };
    static char *alpn[] = {
        "h2",
        "http/1.1"
    };

    if (tls_ctx_init(ctx, TLS_protocol_tls12, 1) != 1
        || tls_ctx_set_cipher_suites(ctx, cipher_suites, 1) != 1
        || tls_ctx_set_supported_groups(ctx, groups, 1) != 1
        || tls_ctx_set_signature_algorithms(ctx, sig_algs, 1) != 1
        || tls_ctx_set_application_layer_protocol_negotiation(ctx, alpn, 2) != 1) {
        return -1;
    }
    return 1;
}

static int client_hello_contains_h2(const uint8_t *record)
{
    int protocol;
    const uint8_t *random;
    const uint8_t *session_id;
    size_t session_id_len;
    const uint8_t *cipher_suites;
    size_t cipher_suites_len;
    const uint8_t *exts;
    size_t exts_len;

    if (tls_record_get_handshake_client_hello(
            record, &protocol, &random, &session_id, &session_id_len,
            &cipher_suites, &cipher_suites_len, &exts, &exts_len) != 1) {
        return 0;
    }
    if (protocol != TLS_protocol_tls12) {
        return 0;
    }

    while (exts_len) {
        int type;
        const uint8_t *data;
        size_t data_len;
        if (tls_ext_from_bytes(&type, &data, &data_len, &exts, &exts_len) != 1) {
            return 0;
        }
        if (type == TLS_extension_application_layer_protocol_negotiation) {
            const uint8_t *names;
            size_t names_len;
            const uint8_t *name;
            size_t name_len;
            if (tls_application_layer_protocol_negotiation_from_bytes(
                    &names, &names_len, data, data_len) != 1
                || tls_uint8array_from_bytes(&name, &name_len, &names, &names_len) != 1) {
                return 0;
            }
            return name_len == 2 && memcmp(name, "h2", 2) == 0;
        }
    }
    return 0;
}

static int build_server_hello(uint8_t *record, size_t *record_len)
{
    uint8_t exts[64];
    uint8_t *p = exts;
    size_t exts_len = 0;
    uint8_t random[32] = {0};
    char *selected = "h2";

    random[31] = 1;
    if (tls_application_layer_protocol_negotiation_selected_ext_to_bytes(
            selected, &p, &exts_len) != 1) {
        return -1;
    }
    memset(record, 0, TLS_MAX_RECORD_SIZE);
    if (tls_record_set_protocol(record, TLS_protocol_tls12) != 1
        || tls_record_set_handshake_server_hello(
               record, record_len, TLS_protocol_tls12, random,
               NULL, 0, TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256,
               exts, exts_len) != 1
        || tls_record_set_protocol(record, TLS_protocol_tls12) != 1) {
        return -1;
    }
    return 1;
}

int main(void)
{
    TLS_CTX ctx;
    TLS_CONNECT conn;
    probe_io io = {0};
    TLS_IO callbacks = {&io, probe_send, probe_recv};
    size_t server_hello_len = 0;
    int rc = 1;

    fprintf(stderr, "alpn-probe: abi ctx=%zu/%zu conn=%zu/%zu\n",
            sizeof(TLS_CTX), tls_ctx_sizeof(), sizeof(TLS_CONNECT), tls_connect_sizeof());
    if (sizeof(TLS_CTX) != tls_ctx_sizeof() || sizeof(TLS_CONNECT) != tls_connect_sizeof()) {
        return 9;
    }

    fprintf(stderr, "alpn-probe: configure ctx\n");
    if (configure_tls12_client(&ctx) != 1) {
        return 10;
    }
    fprintf(stderr, "alpn-probe: init conn\n");
    if (tls_init(&conn, &ctx) != 1 || tls_set_io(&conn, &callbacks) != 1) {
        tls_ctx_cleanup(&ctx);
        return 11;
    }

    fprintf(stderr, "alpn-probe: send client hello\n");
    if (tls_send_client_hello(&conn) != 1) {
        rc = 12;
        goto end;
    }
    fprintf(stderr, "alpn-probe: parse client hello bytes=%zu\n", io.output_len);
    if (!client_hello_contains_h2(io.output)) {
        rc = 13;
        goto end;
    }

    fprintf(stderr, "alpn-probe: build server hello\n");
    if (build_server_hello(io.input, &server_hello_len) != 1) {
        rc = 14;
        goto end;
    }
    io.input_len = server_hello_len;
    io.input_off = 0;

    fprintf(stderr, "alpn-probe: recv server hello bytes=%zu\n", server_hello_len);
    if (tls_recv_server_hello(&conn) != 1) {
        rc = 15;
        goto end;
    }
    fprintf(stderr, "alpn-probe: validate selected alpn\n");
    if (!conn.alpn_selected || strcmp(conn.alpn_selected, "h2") != 0
        || !conn.application_layer_protocol_negotiation) {
        rc = 16;
        goto end;
    }

    rc = 0;

end:
    fprintf(stderr, "alpn-probe: cleanup rc=%d\n", rc);
    tls_cleanup(&conn);
    tls_ctx_cleanup(&ctx);
    return rc;
}
