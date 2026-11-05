#include <libpq-fe.h>
#include <stddef.h>

int main(void) {
  static const char *const keywords[] = {
      "host", "port", "sslmode", "channel_binding", "connect_timeout", NULL};
  static const char *const values[] = {
      "127.0.0.1", "1", "disable", "require", "1", NULL};
  unsigned char binding[32] = {0};
  PGconn *conn = PQconnectStartParams(keywords, values, 0);
  int accepted;
  int rejected;

  if (conn == NULL)
    return 1;
#ifndef LIBPQ_HAS_EXTERNAL_CHANNEL_BINDING
  PQfinish(conn);
  return 2;
#else
  accepted = PQsetExternalChannelBinding(
      conn, "tls-server-end-point", binding, sizeof(binding));
  rejected = PQsetExternalChannelBinding(
      conn, "tls-exporter", binding, sizeof(binding));
  PQfinish(conn);
  return accepted == 1 && rejected == 0 ? 0 : 3;
#endif
}
