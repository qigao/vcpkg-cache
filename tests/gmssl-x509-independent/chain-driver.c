/* Test-only, installed-provider driver. No certificate policy in this wrapper. */
#include <gmssl/x509_cer.h>
#include <stdint.h>
#include <stdio.h>

#define INPUT_CAPACITY 8192u

static int read_bounded(const char *path, uint8_t *buf, size_t *len)
{
    FILE *fp = fopen(path, "rb");
    int extra;
    int failed;
    if (!fp) return 0;
    *len = fread(buf, 1, INPUT_CAPACITY, fp);
    extra = fgetc(fp);
    failed = ferror(fp) || extra != EOF || *len == 0;
    if (fclose(fp) != 0) failed = 1;
    return !failed;
}

int main(int argc, char **argv)
{
    uint8_t chain[INPUT_CAPACITY];
    uint8_t root[INPUT_CAPACITY];
    size_t chain_len = 0;
    size_t root_len = 0;
    int verify_result = X509_verify_ok;
    int ret;
    if (argc != 3 || !read_bounded(argv[1], chain, &chain_len)
                  || !read_bounded(argv[2], root, &root_len)) {
        fputs("driver input error (not a certificate rejection)\n", stderr);
        return 2;
    }
    ret = x509_certs_verify(chain, chain_len, X509_cert_chain_server,
        root, root_len, NULL, 0, NULL, 0, X509_MAX_VERIFY_DEPTH, &verify_result);
    printf("{\"return\":%d,\"verify_result\":%d}\n", ret, verify_result);
    if (ret == 1) return verify_result == X509_verify_ok ? 0 : 2;
    return (ret == -1 || ret == 0) ? 1 : 2;
}
