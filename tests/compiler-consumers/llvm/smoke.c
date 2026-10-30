#include <stdint.h>
#include <stdio.h>
int main(void) {
    uint32_t value = UINT32_C(41) + UINT32_C(1);
    if (value != 42u) return 1;
    puts("LLVM-MinGW C smoke PASS");
    return 0;
}
