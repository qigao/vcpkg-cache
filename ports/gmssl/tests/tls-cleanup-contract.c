#include <gmssl/tls.h>

#include <stddef.h>
#include <stdint.h>
#include <string.h>

int main(void)
{
    TLS_CONNECT conn;
    static const uint8_t hello_a[] = {0x01, 0x02, 0x03, 0x04};
    static const uint8_t hello_b[] = {0x05, 0x06, 0x07};

    memset(&conn, 0, sizeof(conn));
    if (tls_client_verify_init(&conn.client_verify_ctx) != 1)
        return 1;
    if (tls_client_verify_update(
            &conn.client_verify_ctx, hello_a, sizeof(hello_a)) != 1)
        return 2;
    if (tls_client_verify_update(
            &conn.client_verify_ctx, hello_b, sizeof(hello_b)) != 1)
        return 3;
    if (conn.client_verify_ctx.index != 2
        || conn.client_verify_ctx.handshake[0] == NULL
        || conn.client_verify_ctx.handshake[1] == NULL)
        return 4;

    tls_cleanup(&conn);

    if (conn.client_verify_ctx.index != 0
        || conn.client_verify_ctx.handshake[0] != NULL
        || conn.client_verify_ctx.handshake[1] != NULL)
        return 5;

    /* Cleanup must remain idempotent after the secure clear. */
    tls_cleanup(&conn);
    return 0;
}
