#include <gmssl/des.h>

#include <stdint.h>
#include <string.h>

static const uint8_t key[DES_KEY_SIZE] = {
    0x01, 0x23, 0x45, 0x67, 0x89, 0xab, 0xcd, 0xef};

static const uint8_t iv[DES_BLOCK_SIZE] = {
    0x12, 0x34, 0x56, 0x78, 0x90, 0xab, 0xcd, 0xef};

static const uint8_t plaintext[24] = {
    0x4e, 0x6f, 0x77, 0x20, 0x69, 0x73, 0x20, 0x74,
    0x68, 0x65, 0x20, 0x74, 0x69, 0x6d, 0x65, 0x20,
    0x66, 0x6f, 0x72, 0x20, 0x61, 0x6c, 0x6c, 0x20};

static const uint8_t ciphertext[24] = {
    0xe5, 0xc7, 0xcd, 0xde, 0x87, 0x2b, 0xf2, 0x7c,
    0x43, 0xe9, 0x34, 0x00, 0x8c, 0x38, 0x9c, 0x0f,
    0x68, 0x37, 0x88, 0x49, 0x9a, 0x7c, 0x05, 0xf6};

int main(void)
{
    uint8_t encrypted[sizeof(plaintext)];
    uint8_t decrypted[sizeof(plaintext)];
    uint8_t inplace[sizeof(plaintext)];

    if (des_cbc_encrypt(key, iv, plaintext, sizeof(plaintext), encrypted) != 1)
        return 1;
    if (memcmp(encrypted, ciphertext, sizeof(ciphertext)) != 0)
        return 2;

    if (des_cbc_decrypt(key, iv, encrypted, sizeof(encrypted), decrypted) != 1)
        return 3;
    if (memcmp(decrypted, plaintext, sizeof(plaintext)) != 0)
        return 4;

    memcpy(inplace, plaintext, sizeof(inplace));
    if (des_cbc_encrypt(key, iv, inplace, sizeof(inplace), inplace) != 1)
        return 5;
    if (memcmp(inplace, ciphertext, sizeof(ciphertext)) != 0)
        return 6;
    if (des_cbc_decrypt(key, iv, inplace, sizeof(inplace), inplace) != 1)
        return 7;
    if (memcmp(inplace, plaintext, sizeof(plaintext)) != 0)
        return 8;

    if (des_cbc_encrypt(key, iv, NULL, 0u, NULL) != 1)
        return 9;
    if (des_cbc_encrypt(key, iv, plaintext, 7u, encrypted) != -1)
        return 10;
    if (des_cbc_encrypt(NULL, iv, plaintext, sizeof(plaintext), encrypted) != -1)
        return 11;

    return 0;
}
