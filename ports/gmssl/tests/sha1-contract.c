#include <gmssl/sha1.h>

#include <stdint.h>
#include <string.h>

int main(void) {
  static const uint8_t expected[SHA1_DIGEST_SIZE] = {
      0xa9,0x99,0x3e,0x36,0x47,0x06,0x81,0x6a,0xba,0x3e,
      0x25,0x71,0x78,0x50,0xc2,0x6c,0x9c,0xd0,0xd8,0x9d};
  SHA1_CTX ctx;
  uint8_t digest[SHA1_DIGEST_SIZE];

  sha1_init(&ctx);
  sha1_update(&ctx, (const uint8_t *)"abc", 3u);
  sha1_finish(&ctx, digest);
  return memcmp(digest, expected, sizeof(digest)) == 0 ? 0 : 1;
}
