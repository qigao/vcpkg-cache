#include <gmssl/tls.h>

#include <stdint.h>
#include <stdio.h>
#include <string.h>

enum {
    PIPE_CAPACITY = 17 * 1024,
    SEND_CHUNK = 37,
    RECV_CHUNK = 29,
    MAX_STEPS = 200000
};

typedef struct {
    uint8_t data[PIPE_CAPACITY];
    size_t used;
    size_t high_water;
} mem_pipe;

typedef struct {
    mem_pipe *rx;
    mem_pipe *tx;
    unsigned send_calls;
    unsigned recv_calls;
    int saw_send_again;
    int saw_recv_again;
    int saw_partial_send;
    int saw_partial_recv;
} mem_endpoint;

static tls_ret_t mem_send(void *user, const void *buf, size_t len, int flags)
{
    mem_endpoint *ep = (mem_endpoint *)user;
    size_t free_space;
    size_t n;
    (void)flags;

    if (!ep || !buf || !len || !ep->tx) return TLS_ERROR_SYSCALL;
    ep->send_calls++;

    /* Force deterministic backpressure even when the peer queue has room. */
    if ((ep->send_calls % 7u) == 0u) {
        ep->saw_send_again = 1;
        return TLS_ERROR_SEND_AGAIN;
    }

    free_space = PIPE_CAPACITY - ep->tx->used;
    if (!free_space) {
        ep->saw_send_again = 1;
        return TLS_ERROR_SEND_AGAIN;
    }
    n = len;
    if (n > SEND_CHUNK) n = SEND_CHUNK;
    if (n > free_space) n = free_space;
    if (n < len) ep->saw_partial_send = 1;

    memcpy(ep->tx->data + ep->tx->used, buf, n);
    ep->tx->used += n;
    if (ep->tx->used > ep->tx->high_water) ep->tx->high_water = ep->tx->used;
    return (tls_ret_t)n;
}

static tls_ret_t mem_recv(void *user, void *buf, size_t len, int flags)
{
    mem_endpoint *ep = (mem_endpoint *)user;
    size_t n;
    (void)flags;

    if (!ep || !buf || !len || !ep->rx) return TLS_ERROR_SYSCALL;
    ep->recv_calls++;

    if (!ep->rx->used) {
        ep->saw_recv_again = 1;
        return TLS_ERROR_RECV_AGAIN;
    }
    n = len;
    if (n > RECV_CHUNK) n = RECV_CHUNK;
    if (n > ep->rx->used) n = ep->rx->used;
    if (n < len) ep->saw_partial_recv = 1;

    memcpy(buf, ep->rx->data, n);
    ep->rx->used -= n;
    if (ep->rx->used) {
        memmove(ep->rx->data, ep->rx->data + n, ep->rx->used);
    }
    return (tls_ret_t)n;
}

static int is_retry(int ret)
{
    return ret == TLS_ERROR_RECV_AGAIN || ret == TLS_ERROR_SEND_AGAIN;
}

static int drive_handshake(TLS_CONNECT *client, TLS_CONNECT *server)
{
    int step;
    int client_done = 0;
    int server_done = 0;

    /* Prove an empty callback queue produces WANT_READ before any peer bytes. */
    {
        int ret = tls_do_handshake(server);
        if (ret != TLS_ERROR_RECV_AGAIN) return -1;
    }

    for (step = 0; step < MAX_STEPS; step++) {
        int ret;

        if (!client_done) {
            ret = tls_do_handshake(client);
            if (ret != 1 && !is_retry(ret)) return -1;
            if (tls_get_handshake_complete(client, &client_done) != 1) return -1;
        }

        if (!server_done) {
            ret = tls_do_handshake(server);
            if (ret != 1 && !is_retry(ret)) return -1;
            if (tls_get_handshake_complete(server, &server_done) != 1) return -1;
        }

        if (client_done && server_done) return 1;
    }
    return -1;
}

static int transfer(TLS_CONNECT *sender, TLS_CONNECT *receiver,
    const uint8_t *input, size_t input_len)
{
    uint8_t output[256];
    size_t sent_total = 0;
    size_t recv_total = 0;
    int step;

    if (input_len > sizeof(output)) return -1;
    memset(output, 0, sizeof(output));

    for (step = 0; step < MAX_STEPS; step++) {
        if (sent_total < input_len) {
            size_t sent = 0;
            int ret = tls_send(sender, input + sent_total, input_len - sent_total, &sent);
            if (ret == 1) {
                if (!sent || sent > input_len - sent_total) return -1;
                sent_total += sent;
            } else if (!is_retry(ret)) {
                return -1;
            }
        }

        if (recv_total < input_len) {
            size_t got = 0;
            int ret = tls_recv(receiver, output + recv_total,
                input_len - recv_total, &got);
            if (ret == 1) {
                if (!got || got > input_len - recv_total) return -1;
                recv_total += got;
            } else if (!is_retry(ret)) {
                return -1;
            }
        }

        if (sent_total == input_len && recv_total == input_len) {
            return memcmp(input, output, input_len) == 0 ? 1 : -1;
        }
    }
    return -1;
}

static int drive_shutdown(TLS_CONNECT *client, TLS_CONNECT *server)
{
    int client_done = 0;
    int server_done = 0;
    int step;

    for (step = 0; step < MAX_STEPS; step++) {
        int ret;
        if (!client_done) {
            ret = tls_shutdown(client);
            if (ret == 1) client_done = 1;
            else if (!is_retry(ret)) return -1;
        }
        if (!server_done) {
            ret = tls_shutdown(server);
            if (ret == 1) server_done = 1;
            else if (!is_retry(ret)) return -1;
        }
        if (client_done && server_done) return 1;
    }
    return -1;
}

int main(int argc, char **argv)
{
    TLS_CTX client_ctx;
    TLS_CTX server_ctx;
    TLS_CONNECT client;
    TLS_CONNECT server;
    mem_pipe c2s;
    mem_pipe s2c;
    mem_endpoint client_ep;
    mem_endpoint server_ep;
    TLS_IO client_io;
    TLS_IO server_io;
    int client_ctx_init = 0;
    int server_ctx_init = 0;
    int client_init = 0;
    int server_init = 0;
    int rc = 1;
    int closed = 0;
    const int cipher = TLS_cipher_ecdhe_ecdsa_with_aes_128_gcm_sha256;
    const int group = TLS_curve_secp256r1;
    const int sig_alg = TLS_sig_ecdsa_secp256r1_sha256;
    static const uint8_t request[] =
        "callback-only request: fragmented TLS without socket ownership";
    static const uint8_t response[] =
        "callback-only response: bounded queue and close_notify";

    if (argc != 5) {
        fprintf(stderr, "usage: %s <ca.pem> <server-cert.pem> <server-key.pem> <key-pass>\n", argv[0]);
        return 2;
    }

    memset(&client_ctx, 0, sizeof(client_ctx));
    memset(&server_ctx, 0, sizeof(server_ctx));
    memset(&client, 0, sizeof(client));
    memset(&server, 0, sizeof(server));
    memset(&c2s, 0, sizeof(c2s));
    memset(&s2c, 0, sizeof(s2c));
    memset(&client_ep, 0, sizeof(client_ep));
    memset(&server_ep, 0, sizeof(server_ep));

    client_ep.rx = &s2c;
    client_ep.tx = &c2s;
    server_ep.rx = &c2s;
    server_ep.tx = &s2c;

    client_io.user = &client_ep;
    client_io.send = mem_send;
    client_io.recv = mem_recv;
    server_io.user = &server_ep;
    server_io.send = mem_send;
    server_io.recv = mem_recv;

    if (tls_ctx_init(&client_ctx, TLS_protocol_tls12, TLS_client_mode) != 1) goto end;
    client_ctx_init = 1;
    if (tls_ctx_init(&server_ctx, TLS_protocol_tls12, TLS_server_mode) != 1) goto end;
    server_ctx_init = 1;

    if (tls_ctx_set_cipher_suites(&client_ctx, &cipher, 1) != 1
        || tls_ctx_set_supported_groups(&client_ctx, &group, 1) != 1
        || tls_ctx_set_signature_algorithms(&client_ctx, &sig_alg, 1) != 1
        || tls_ctx_set_ca_certificates(&client_ctx, argv[1], 5) != 1
        || tls_ctx_set_cipher_suites(&server_ctx, &cipher, 1) != 1
        || tls_ctx_set_supported_groups(&server_ctx, &group, 1) != 1
        || tls_ctx_set_signature_algorithms(&server_ctx, &sig_alg, 1) != 1
        || tls_ctx_add_certificate_chain_and_key(&server_ctx, argv[2], argv[3], argv[4]) != 1) {
        goto end;
    }

    if (tls_init(&client, &client_ctx) != 1) goto end;
    client_init = 1;
    if (tls_init(&server, &server_ctx) != 1) goto end;
    server_init = 1;

    if (tls_set_hostname(&client, "localhost") != 1
        || tls_set_io(&client, &client_io) != 1
        || tls_set_io(&server, &server_io) != 1) {
        goto end;
    }

    if (drive_handshake(&client, &server) != 1) goto end;

    if (!client_ep.saw_recv_again || !server_ep.saw_recv_again
        || !client_ep.saw_send_again || !server_ep.saw_send_again
        || !client_ep.saw_partial_send || !server_ep.saw_partial_send
        || !client_ep.saw_partial_recv || !server_ep.saw_partial_recv) {
        goto end;
    }
    if (c2s.high_water > PIPE_CAPACITY || s2c.high_water > PIPE_CAPACITY) goto end;

    if (transfer(&client, &server, request, sizeof(request) - 1) != 1
        || transfer(&server, &client, response, sizeof(response) - 1) != 1) {
        goto end;
    }

    if (drive_shutdown(&client, &server) != 1) goto end;
    if (tls_get_peer_close_notify(&client, &closed) != 1 || !closed) goto end;
    if (tls_get_peer_close_notify(&server, &closed) != 1 || !closed) goto end;

    printf("GmSSL callback-only TLS 1.2 contract: PASS (c2s high-water=%zu, s2c high-water=%zu)\n",
        c2s.high_water, s2c.high_water);
    rc = 0;

end:
    if (client_init) tls_cleanup(&client);
    if (server_init) tls_cleanup(&server);
    if (client_ctx_init) tls_ctx_cleanup(&client_ctx);
    if (server_ctx_init) tls_ctx_cleanup(&server_ctx);
    return rc;
}
