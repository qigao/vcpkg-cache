/* RFC 8446 4.1.2 / RFC 7685 HRR padding exception.
 * A second ClientHello may add, remove, or resize only this extension
 * without an explicit HRR extension authorization. Every payload octet
 * MUST be zero, including newly introduced or resized padding.
 *
 * Unlike all other extension checks, this helper may be used even when
 * ClientHello1 had no padding extension. It does not authorize duplicates,
 * nonzero data, modified non-padding extensions, or unbounded allocation.
 */
#ifndef GMSSL_TLS13_HRR_PADDING_H
#define GMSSL_TLS13_HRR_PADDING_H

#include <stddef.h>
#include <stdint.h>

static int gmssl_tls13_hrr_padding_valid(const uint8_t *data, size_t length)
{
    size_t i;
    unsigned int not_zero = 0u;
    if (!data && length) return 0;
    for (i = 0; i < length; ++i)
        not_zero |= (unsigned int)data[i];
    return not_zero == 0u;
}
#endif
