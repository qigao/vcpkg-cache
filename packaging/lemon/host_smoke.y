%name LemonSmoke
%token_prefix TOK_
%token_type {int}
%default_type {int}
%extra_argument {SmokeContext *ctx}
%include {
#include "smoke_types.h"
}
%syntax_error { ctx->errors++; }
%parse_failure { ctx->errors++; }
%parse_accept { ctx->accepted++; }
%stack_overflow { ctx->errors++; }
%left PLUS.
%left STAR.

result ::= expr(A). { ctx->value = A; }
expr(A) ::= INT(B). { A = B; }
expr(A) ::= expr(B) PLUS expr(C). { A = B + C; }
expr(A) ::= expr(B) STAR expr(C). { A = B * C; }
expr(A) ::= LPAREN expr(B) RPAREN. { A = B; }
