#include <stdint.h>
#include <stdio.h>
int main(void) {
    uint32_t value = 6u * 7u;
    if (value != 42u) return 1;
    puts("TinyCC C smoke PASS");
    return 0;
}
