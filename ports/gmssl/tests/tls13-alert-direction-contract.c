/* Private GmSSL 3.2.0 regression: outbound fatal alert keys and nonce
 * must follow the actual TLS local write direction (not the failed read).
 * Fail-closed, zero plaintext admission, no client/server nonce aliasing. */
#include <gmssl/tls.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct alert_sink {
    uint8_t bytes[TLS_MAX_RECORD_SIZE];
    size_t len;
    unsigned int writes;
} alert_sink;

static tls_ret_t send_ciphertext(void *arg, const void *data, size_t len, int flags)
{
    alert_sink *sink = (alert_sink *)arg;
    (void)flags;
    if (!sink || !data || len > sizeof(sink->bytes) || sink->len) return -1;
    memcpy(sink->bytes, data, len);
    sink->len = len;
    sink->writes++;
    return (tls_ret_t)len;
}

static tls_ret_t no_peer_bytes(void *arg, void *data, size_t len, int flags)
{
    (void)arg;
    (void)data;
    (void)len;
    (void)flags;
    return TLS_ERROR_RECV_AGAIN;
}

static int test_local_alert(int client_mode)
{
    TLS_CTX ctx = {0};
    TLS_CONNECT conn = {0};
    alert_sink sink = {0};
    uint8_t local_key[16] = {0};
    uint8_t opposite_key[16] = {0};
    uint8_t decrypted[TLS_MAX_RECORD_SIZE] = {0};
    uint8_t initial_seq[8] = {0};
    size_t decrypted_len = 0;
    const BLOCK_CIPHER_KEY *cipher_key;
    const BLOCK_CIPHER_KEY *other_key;
    const uint8_t *iv;
    const uint8_t *seq;
    TLS_IO io = {&sink, send_ciphertext, no_peer_bytes};

    local_key[0] = (uint8_t)(client_mode ? 0x91 : 0x72);
    opposite_key[0] = (uint8_t)(client_mode ? 0x72 : 0x91);
    ctx.is_client = client_mode;
    ctx.protocol = TLS_protocol_tls13;
    conn.ctx = &ctx;
    conn.protocol = TLS_protocol_tls13;
    conn.cipher_suite = TLS_cipher_aes_128_gcm_sha256;
    conn.cipher = BLOCK_CIPHER_aes128();
    conn.handshake_state = 0; /* Encrypted-record alert path. */
    if (block_cipher_set_encrypt_key(&conn.client_write_key, conn.cipher,
        client_mode ? local_key : opposite_key) != 1) return 1;
    if (block_cipher_set_encrypt_key(&conn.server_write_key, conn.cipher,
        client_mode ? opposite_key : local_key) != 1) return 2;
    if (tls_set_io(&conn, &io) != 1) return 3;

    if (tls13_send_alert(&conn, TLS_alert_bad_record_mac) != 1) return 4;
    if (sink.writes != 1u || sink.len == 0) return 5;
    if (conn.server_seq_num[7] != (client_mode ? 0u : 1u)) return 6;
    if (conn.client_seq_num[7] != (client_mode ? 1u : 0u)) return 7;

    cipher_key = client_mode ? &conn.client_write_key : &conn.server_write_key;
    other_key = client_mode ? &conn.server_write_key : &conn.client_write_key;
    iv = client_mode ? conn.client_write_iv : conn.server_write_iv;
    seq = initial_seq;
    if (tls13_record_decrypt(conn.cipher_suite, cipher_key, iv,
                            seq, sink.bytes, sink.len, decrypted,
                            &decrypted_len) != 1) return 8;
    if (decrypted_len < 7u || decrypted[0] != TLS_record_alert ||
        decrypted[5] != TLS_alert_level_fatal ||
        decrypted[6] != TLS_alert_bad_record_mac) return 9;

    decrypted_len = 0;
    if (tls13_record_decrypt(conn.cipher_suite, other_key, iv,
                            seq, sink.bytes, sink.len, decrypted,
                            &decrypted_len) == 1) return 10;
    tls_cleanup(&conn);
    tls_ctx_cleanup(&ctx);
    return 0;
}

int main(void)
{
    int client = test_local_alert(1);
    int server = test_local_alert(0);
    if (client || server) {
        fprintf(stderr,
            "GmSSL TLS13 Fatal Alert write direction: client=%d server=%d\n",
            client, server);
        return 1;
    }
    puts("GmSSL TLS13 Fatal Alert write direction: PASS");
    return 0;
}
