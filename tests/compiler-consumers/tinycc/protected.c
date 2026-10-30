#include <stdio.h>
#include <string.h>
#ifndef __TINYC__
#error "This fixture must be compiled by native TinyCC."
#endif
#ifndef OBFH_TEST_SEED
#error "Test must supply explicit build seed."
#endif
/* TinyCC obfuscation applies after system headers, to these functions only. */
#define OBFH_DISABLE_ANTIDEBUG 1
#define OBFH_FAKE_SIGNATURES 0
#define OBFH_SEED OBFH_TEST_SEED
#include "obfus.h"
int main(void) {
    const char *s = HIDE_STRING("native-tcc-protection");
    if (strcmp(s, "native-tcc-protection") != 0) return 1;
    if (VM_ADD(5, 7) != 12) return 2;
    puts("TinyCC obfus.h semantic smoke PASS");
    return 0;
}
