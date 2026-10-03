#include <gmssl/tls.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>

int main(void)
{
    TLS_CONNECT conn;
    static const uint8_t transcript[] = {1u, 2u, 3u, 4u, 5u, 6u, 7u, 8u};

    for (size_t iteration = 0u; iteration < 64u; ++iteration) {
        memset(&conn, 0, sizeof(conn));
        if (tls_client_verify_init(&conn.client_verify_ctx) != 1) return 1;
        for (size_t index = 0u; index < 4u; ++index) {
            if (tls_client_verify_update(
                    &conn.client_verify_ctx, transcript, sizeof(transcript)) != 1)
                return 2;
        }
        tls_cleanup(&conn);
        if (conn.client_verify_ctx.index != 0) return 3;
        for (size_t index = 0u; index < 8u; ++index) {
            if (conn.client_verify_ctx.handshake[index] != NULL
                || conn.client_verify_ctx.handshake_len[index] != 0u)
                return 4;
        }
    }
    return 0;
}
