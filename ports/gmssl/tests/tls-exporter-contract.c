#include <gmssl/tls.h>
#include <gmssl/digest.h>

#include <stdio.h>
#include <string.h>

static const unsigned char expected_tls12[32] = {
  0xd0,0xb2,0x2f,0x03,0xe1,0xb8,0x89,0xac,
  0xa3,0xc8,0x30,0x3d,0x57,0xba,0x67,0x7d,
  0x4a,0x2f,0x35,0xf0,0xed,0xfd,0x63,0xb9,
  0xbe,0x6e,0x1b,0x65,0xf2,0xc2,0x64,0x59
};

static const unsigned char expected_tls13[32] = {
  0x34,0xa9,0x3b,0x1d,0xd3,0xc2,0xb6,0x3e,
  0xbc,0x1b,0xce,0xd0,0xd7,0xd3,0x7a,0xde,
  0x4e,0x53,0xc0,0x57,0xe4,0xd3,0x68,0x57,
  0x8a,0x5b,0xef,0x73,0x77,0x1e,0x2a,0x1b
};

int main(void)
{
  TLS_CONNECT conn;
  unsigned char out[32];
  unsigned char no_context[32];
  size_t i;
  static const char label[] = "EXPORTER-Channel-Binding";

  memset(&conn, 0, sizeof(conn));
  conn.protocol = TLS_protocol_tls12;
  conn.digest = DIGEST_sha256();
  conn.handshake_state = TLS_state_handshake_over;
  for (i = 0; i < sizeof(conn.master_secret); i++) conn.master_secret[i] = (unsigned char)i;
  for (i = 0; i < sizeof(conn.client_random); i++) conn.client_random[i] = (unsigned char)i;
  for (i = 0; i < sizeof(conn.server_random); i++) conn.server_random[i] = (unsigned char)(32u + i);

  if (tls_export_keying_material(&conn, out, sizeof(out), label, NULL, 0, 1) != 1) return 1;
  if (memcmp(out, expected_tls12, sizeof(out)) != 0) return 2;
  if (tls_export_keying_material(&conn, no_context, sizeof(no_context), label, NULL, 0, 0) != 1) return 3;
  if (memcmp(out, no_context, sizeof(out)) == 0) return 4;

  memset(&conn, 0, sizeof(conn));
  conn.protocol = TLS_protocol_tls13;
  conn.digest = DIGEST_sha256();
  conn.handshake_state = TLS_state_handshake_over;
  for (i = 0; i < sizeof(conn.exporter_master_secret); i++) {
    conn.exporter_master_secret[i] = (unsigned char)i;
  }

  if (tls_export_keying_material(&conn, out, sizeof(out), label, NULL, 0, 1) != 1) return 5;
  if (memcmp(out, expected_tls13, sizeof(out)) != 0) return 6;
  if (tls_export_keying_material(&conn, no_context, sizeof(no_context), label, NULL, 0, 0) != 1) return 7;
  if (memcmp(out, no_context, sizeof(out)) != 0) return 8;

  conn.handshake_state = 0;
  if (tls_export_keying_material(&conn, out, sizeof(out), label, NULL, 0, 1) == 1) return 9;

  puts("GmSSL TLS exporter contract: PASS");
  return 0;
}
