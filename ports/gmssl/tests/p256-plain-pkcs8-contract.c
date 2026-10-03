#include <gmssl/pem.h>
#include <gmssl/x509_key.h>

#include <stdio.h>
#include <string.h>

static int write_plain_pkcs8(FILE *fp, const X509_KEY *key)
{
    unsigned char der[512];
    unsigned char *p = der;
    size_t der_len = 0;

    if (!fp || !key) return -1;
    if (x509_private_key_info_to_der(key, &p, &der_len) != 1) return -1;
    if (pem_write(fp, "PRIVATE KEY", der, der_len) != 1) return -1;
    if (fflush(fp) != 0 || fseek(fp, 0, SEEK_SET) != 0) return -1;
    return 1;
}

static int reload_and_compare(FILE *fp, const X509_KEY *original, const char *pass)
{
    X509_KEY loaded;
    int ret = -1;
    memset(&loaded, 0, sizeof(loaded));

    if (fseek(fp, 0, SEEK_SET) != 0) return -1;
    if (x509_private_key_from_file(&loaded, OID_ec_public_key, pass, fp) != 1)
        goto end;
    if (loaded.algor != OID_ec_public_key
        || loaded.algor_param != OID_secp256r1
        || x509_public_key_equ(&loaded, original) != 1)
        goto end;
    ret = 1;

end:
    x509_key_cleanup(&loaded);
    return ret;
}

int main(void)
{
    X509_KEY original;
    FILE *fp = NULL;
    int curve_oid = OID_secp256r1;
    int rc = 1;

    memset(&original, 0, sizeof(original));
    if (x509_key_generate(
            &original, OID_ec_public_key, &curve_oid, sizeof(curve_oid)) != 1) {
        rc = 2;
        goto end;
    }

    fp = tmpfile();
    if (!fp) {
        rc = 3;
        goto end;
    }
    if (write_plain_pkcs8(fp, &original) != 1) {
        rc = 4;
        goto end;
    }
    if (reload_and_compare(fp, &original, "") != 1) {
        rc = 5;
        goto end;
    }
    if (reload_and_compare(fp, &original, NULL) != 1) {
        rc = 6;
        goto end;
    }

    puts("GmSSL P-256 plain PKCS8 identity contract: PASS");
    rc = 0;

end:
    if (fp) fclose(fp);
    x509_key_cleanup(&original);
    return rc;
}
