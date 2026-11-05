#include "smoke_types.h"
#include "host_smoke.h"
#include <stdio.h>
#include <stdlib.h>

static int check(const int *tokens, const int *values, size_t count, int expected, int invalid) {
    SmokeContext context = {0, 0, 0};
    void *parser = LemonSmokeAlloc(malloc);
    if (!parser) return 1;
    for (size_t i = 0; i < count; ++i) LemonSmoke(parser, tokens[i], values[i], &context);
    LemonSmoke(parser, 0, 0, &context);
    LemonSmokeFree(parser, free);
    if (invalid) return context.errors == 0;
    return context.errors != 0 || context.accepted != 1 || context.value != expected;
}

int main(void) {
    const int a[] = {TOK_INT, TOK_PLUS, TOK_INT, TOK_STAR, TOK_INT};
    const int av[] = {1, 0, 2, 0, 3};
    const int b[] = {TOK_LPAREN, TOK_INT, TOK_PLUS, TOK_INT, TOK_RPAREN, TOK_STAR, TOK_INT};
    const int bv[] = {0, 1, 0, 2, 0, 0, 3};
    const int bad[] = {TOK_INT, TOK_PLUS, TOK_STAR, TOK_INT};
    const int badv[] = {1, 0, 0, 2};
    if (check(a, av, sizeof(a)/sizeof(a[0]), 7, 0) ||
        check(b, bv, sizeof(b)/sizeof(b[0]), 9, 0) ||
        check(bad, badv, sizeof(bad)/sizeof(bad[0]), 0, 1)) return 1;
    puts("paired Lemon/template: precedence=7 parentheses=9 invalid-input=rejected");
    return 0;
}
