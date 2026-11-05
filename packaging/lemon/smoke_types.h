#ifndef QIGAO_LEMON_SMOKE_TYPES_H
#define QIGAO_LEMON_SMOKE_TYPES_H
#include <stddef.h>
typedef struct SmokeContext { int value, accepted, errors; } SmokeContext;
void *LemonSmokeAlloc(void *(*allocate)(size_t));
void LemonSmoke(void *parser, int token, int value, SmokeContext *context);
void LemonSmokeFree(void *parser, void (*deallocate)(void *));
#endif
