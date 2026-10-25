/* Private RFC 8446 D.4 TLS 1.3 compatibility ChangeCipherSpec admission.
 *
 * A peer may emit one *unencrypted* dummy CCS record between the first
 * ClientHello and its Finished. It carries exactly one byte (0x01) and is
 * NOT part of the transcript hash, handshake fragments, or record sequence.
 *
 * The parser is deliberately independent of GmSSL runtime structures, so
 * malformed and repeated records are testable without network timing.
 *  1 = valid bounded compatibility CCS consumed
 *  0 = not a CCS record; normal TLS1.3 processing continues
 * -1 = invalid/excess CCS: caller must fail closed with a fatal alert
 *
 * Never use this parser for TLS1.2, TLCP, post-handshake traffic, or a
 * pending handshake fragment. Those gates remain the native TLS owner.
 */
#ifndef GMSSL_TLS13_COMPAT_CCS_H
#define GMSSL_TLS13_COMPAT_CCS_H
#include <stddef.h>
#include <stdint.h>

static int gmssl_tls13_compat_ccs_admit(
    const uint8_t *record, size_t record_size,
    size_t handshake_fragment_unconsumed, size_t handshake_message_len,
    unsigned int *accepted_count)
{
    /* One peer-directed compatibility record per connection is enough for
     * the well-formed TLS1.3 OpenSSL middlebox profile. No unbounded loop. */
    static const uint8_t exact_dummy_ccs[6] = {
        0x14, 0x03, 0x03, 0x00, 0x01, 0x01
    };
    size_t i;
    unsigned int difference = 0u;

    if (record == NULL || accepted_count == NULL || record_size < 1u)
        return -1;
    if (record[0] != exact_dummy_ccs[0])
        return 0;
    if (record_size != sizeof(exact_dummy_ccs) ||
        handshake_fragment_unconsumed != 0u ||
        handshake_message_len != 0u ||
        *accepted_count >= 1u)
        return -1;
    for (i = 0u; i < sizeof(exact_dummy_ccs); ++i)
        difference |= (unsigned int)(record[i] ^ exact_dummy_ccs[i]);
    if (difference != 0u)
        return -1;
    ++*accepted_count;
    return 1;
}
#endif
