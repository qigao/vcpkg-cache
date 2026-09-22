#include <flowmq_socket.h>
#include <salts_error.h>

#include <stdio.h>

int main(void) {
  int rc = 1;
  flowmq_ctx_t *ctx = flowmq_ctx_new();
  flowmq_socket_t *socket = NULL;

  if (ctx == NULL) return 2;
  socket = flowmq_socket(ctx, FLOWMQ_PAIR);
  if (socket == NULL) goto cleanup;
  if (flowmq_close(socket) != SALTS_OK) goto cleanup;
  socket = NULL;
  if (flowmq_ctx_term(ctx) != SALTS_OK) return 3;
  ctx = NULL;
  puts("FLOWMQ_NATIVE_REAL_ABI_OK");
  return 0;

cleanup:
  if (socket != NULL) (void)flowmq_close(socket);
  if (ctx != NULL) (void)flowmq_ctx_term(ctx);
  return rc;
}
