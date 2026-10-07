# GmSSL TLS interoperability adaptations

The port pins upstream in `portfile.cmake`. Its private TLS provider is linked
statically into CNet; it does not change the public CNet API.

## Encrypted TLS 1.3 handshake framing

`handshake-framing.cmake` separates authenticated record payloads from initial
handshake messages in both client and server receive states. RFC 8446 section
[5.1](https://www.rfc-editor.org/rfc/rfc8446.html#section-5.1) permits coalesced
messages and messages fragmented across records. Relaxing the existing parser's
length equality would discard trailing messages and hash the wrong transcript.

Each connection owns one additional `TLS_MAX_RECORD_SIZE` fragment buffer
(18,437 bytes) and bounded cursor state. The existing `plain_record` holds the
message under assembly. The progress caller is the sole writer; nonblocking
receive retries preserve both partial ciphertext and plaintext. Complete
messages are borrowed only until the next receive/send operation. No new queue,
thread, heap allocation, or cleanup obligation is introduced. Connection cleanup
already clears the entire structure.

The existing maximum handshake body size, `TLS_MAX_HANDSHAKE_DATA_SIZE`, remains
unchanged. Oversized messages, empty handshake fragments, interleaved content,
and trailing bytes after Finished are rejected. Record sequence numbers advance
once per authenticated record; transcript updates remain in the message-specific
state handlers. Optional CertificateRequest lookahead retains one message.
TLS 1.2, pre-key-exchange hello framing, and post-handshake processing are outside
this adaptation's scope.

## ECDSA DER scalar width

`ecdsa-der-width.cmake` left-pads variable-width DER INTEGER magnitudes before
converting them to fixed-width P-256 scalars. Reading 32 bytes directly from a
short magnitude both reads beyond its value and rejects otherwise valid
CertificateVerify signatures. Existing DER validation and cryptographic
verification remain enabled.

`tls13-optional-inputs.cmake` initializes absent SNI and certificate-signature
extension values/counts before certificate selection. Debug runtime checks must
not encounter uninitialized values when an IP peer sends no SNI or a
CertificateRequest omits `signature_algorithms_cert`.

## Integration and rollback

Port revision 4 changes `sizeof(TLS_CONNECT)`. Rebuild the provider and every
consumer of its headers together; CNet's existing runtime size probes reject
mismatched headers/libraries. Consumers must update their registry baseline to
this port revision. Rollback restores the previous baseline and rebuilds the SDK;
do not swap a provider library underneath headers from another revision.

Regression coverage lives in Salts' formal CTest suites
`cnet_tls_handshake_framing_test`, `cnet_tls_signature_test`, and `cnet_tls_test`.
Flowie's MQTT client, external HTTPS authentication, JWKS, and transport suites
exercise the installed SDK, including a BoringSSL server as an independent peer.
