/* Exercise the packaged generator, syntax and both Unicode 17 input tables. */
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>

/*!include:re2c "unicode_properties.re" */
/*!include:re2c "unicode_categories.re" */

static int classify(const unsigned char *input) {
    const unsigned char *YYCURSOR = input;
    const unsigned char *YYMARKER;
    /*!re2c
        re2c:define:YYCTYPE = "unsigned char";
        re2c:encoding:utf8 = 1;
        re2c:encoding-policy = fail;
        re2c:yyfill:enable = 0;
        XID_Start    { return 1; }
        XID_Continue { return 2; }
        White_Space  { return 3; }
        [^]          { return 4; }
        *            { return 0; }
    */
}

static int decimal(uint32_t scalar) {
    const uint32_t *YYCURSOR = &scalar;
    /*!re2c
        re2c:define:YYCTYPE = "uint32_t";
        re2c:encoding:utf32 = 1;
        re2c:yyfill:enable = 0;
        Nd { return 1; }
        *  { return 0; }
    */
}

int main(void) {
    /* Padding makes all four-byte UTF-8 lookahead reads valid, including
       malformed input. This is a package smoke test, not a streaming API. */
    static const struct {
        unsigned char bytes[8];
        int expected;
    } cases[] = {
        {{0x41}, 1},                         /* A */
        {{0xce, 0xb1}, 1},                   /* Greek alpha */
        {{0xe4, 0xb8, 0xad}, 1},             /* CJK letter */
        {{0xf0, 0x90, 0x90, 0x80}, 1},       /* Deseret U+10400 */
        {{0x30}, 2},                         /* Decimal digit */
        {{0xcc, 0x81}, 2},                   /* Combining acute */
        {{0x20}, 3},                         /* Space */
        {{0xc2, 0xa0}, 3},                   /* No-break space */
        {{0xf0, 0x9f, 0x98, 0x80}, 4},       /* Emoji U+1F600 */
        {{0xff}, 0},                         /* Invalid leading byte */
        {{0xc0, 0x80}, 0},                   /* Overlong encoding */
        {{0xed, 0xa0, 0x80}, 0},             /* UTF-16 surrogate */
        {{0xf0, 0x9f, 0x98}, 0},             /* Truncated sequence */
    };
    size_t i;
    for (i = 0; i < sizeof(cases) / sizeof(cases[0]); ++i) {
        if (classify(cases[i].bytes) != cases[i].expected) {
            fprintf(stderr, "Unicode host smoke case %zu failed\n", i);
            return 1;
        }
    }
    if (!decimal(0x34) || !decimal(0x664) || !decimal(0x1d7d2) ||
        decimal(0x41)) {
        fputs("Unicode decimal category smoke failed\n", stderr);
        return 1;
    }
    puts("RE2C_UNICODE_HOST_SMOKE_OK utf8_cases=13 decimal_cases=4");
    return 0;
}
