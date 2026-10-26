# Crypto-owned POST-IMPORT protocol fix, separate from 40 original
# adaptations and five existing Crypto undefined-behavior hardenings.
# RFC 8446 section 5.1 / appendix D.4 allows a single strict dummy
# ChangeCipherSpec between HRR and the second ClientHello.
#
# The native opaque Crypto C11 facade enables accept_change_cipher_spec
# ONLY for its TLS1.3 server profile. No public C11 ABI or GmSSL
# private function table is exposed or replaced.
#
# A malformed / duplicate CCS or non-handshake record FAILS CLOSED,
# never skipped, and only one validated 0x01 byte can be discarded.
# The cached first ClientHello, transcript hashes and Finished checks
# remain completely unchanged.
crypto_gmssl_harden_once(
  "${SOURCE_PATH}/include/gmssl/tls.h"
  [==[	// HelloRetryRequest
	int hello_retry_request;]==]
  [==[	// HelloRetryRequest
	int hello_retry_request;
	// Private per-session bounded TLS1.3 compatibility CCS after HRR.
	unsigned int crypto_hrr_ccs_seen;]==])

crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/tls13.c"
  [==[	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv ClientHello again\n");]==]
  [==[	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	// OpenSSL3's middlebox compatibility mode may send exactly one
	// RFC8446 dummy CCS (type 20, legacy 0x0303, length 1, byte 0x01)
	// before ClientHello2 after a legitimate HelloRetryRequest.
	// Consume only when explicitly configured in the private TLS_CTX.
	// Returning AGAIN allows the existing state machine to receive and
	// *fully authenticate* ClientHello2 on its next bounded drive.
	if (tls_record_type(conn->record) == TLS_record_change_cipher_spec) {
		if (!conn->ctx->accept_change_cipher_spec
			|| conn->crypto_hrr_ccs_seen != 0u) {
			tls13_send_alert(conn, TLS_alert_unexpected_message);
			return -1;
		}
		if (conn->recordlen != TLS_RECORD_HEADER_SIZE + 1u
			|| tls_record_protocol(conn->record) != TLS_protocol_tls12
			|| tls_record_get_change_cipher_spec(conn->record) != 1) {
			tls13_send_alert(conn, TLS_alert_decode_error);
			return -1;
		}
		conn->crypto_hrr_ccs_seen = 1u;
		tls_clean_record(conn);
		return TLS_ERROR_RECV_AGAIN;
	}
	if (tls_record_type(conn->record) != TLS_record_handshake) {
		tls13_send_alert(conn, TLS_alert_unexpected_message);
		return -1;
	}
	if(conn->verbose) tls_trace("recv ClientHello again\n");]==])
