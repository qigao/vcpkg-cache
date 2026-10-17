#include <gmssl/tls.h>
#include <stdio.h>
#include <stddef.h>

int main(void)
{
    const size_t header_ctx = sizeof(TLS_CTX);
    const size_t header_connect = sizeof(TLS_CONNECT);
    const size_t library_ctx = tls_ctx_sizeof();
    const size_t library_connect = tls_connect_sizeof();

    printf("TLS_CTX header=%zu library=%zu\n", header_ctx, library_ctx);
    printf("TLS_CONNECT header=%zu library=%zu\n", header_connect, library_connect);
    if (header_ctx != library_ctx || header_connect != library_connect) {
        fputs("GmSSL installed TLS ABI layout mismatch\n", stderr);
        return 1;
    }
    return 0;
}
