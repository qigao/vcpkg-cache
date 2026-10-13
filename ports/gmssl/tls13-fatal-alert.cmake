# GmSSL TLS 1.3 reuses conn->record for both inbound and outbound records.
# After tls_recv_record() completes, recordlen/record_offset still describe
# the just-consumed ClientHello. In tls13_send_alert(), treating this as an
# outstanding outbound record skips alert encoding and tls_io_send() entirely.
#
# Clear *only* an already fully consumed record. A partial outbound send is
# still owned by the provider and must not be erased or retried implicitly.
# Fatal Alert code/level selection remains GmSSL's responsibility.
set(_gmssl_tls13_fatal_alert_c "${SOURCE_PATH}/src/tls13.c")

gmssl_replace_once(
    "${_gmssl_tls13_fatal_alert_c}"
[==[
int tls13_send_alert(TLS_CONNECT *conn, int alert)
{
	int ret;
	size_t padding_len;

	if(conn->verbose) tls_trace("send {Alert}\n");

	if (conn->recordlen == 0) {
]==]
[==[
int tls13_send_alert(TLS_CONNECT *conn, int alert)
{
	int ret;
	size_t padding_len;

	if(conn->verbose) tls_trace("send {Alert}\n");

	/* A complete inbound handshake record must not be mistaken for a
	 * pending outbound alert record. Preserve any partially sent record. */
	if (conn->recordlen != 0 && conn->record_offset == conn->recordlen) {
		tls_clean_record(conn);
	}

	if (conn->recordlen == 0) {
]==]
)


# #196/#1196: tls13_send_alert is shared by client and server. A client
# authenticates inbound records with server_write_*, but *sends* a fatal alert
# using client_write_* and the client write sequence. The older pinned code
# unconditionally used server_write_* even for client-side failures, advancing
# the inbound server sequence and potentially emitting an undecryptable alert.
# Only change the outbound direction selection; preserve the existing
# consumed-record ownership fence, fail-closed behavior and no retry policy.
gmssl_replace_once(
    "${_gmssl_tls13_fatal_alert_c}"
[==[
		default:
			tls13_padding_len_rand(&padding_len);
			if (tls13_record_encrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
				conn->server_seq_num, conn->plain_record, conn->plain_recordlen, padding_len,
				conn->record, &conn->recordlen) != 1) {
				error_print();
				return -1;
			}
			tls_seq_num_incr(conn->server_seq_num);
		}
]==]
[==[
		default: {
			/* A client must never spend the peer's inbound AEAD nonce when
			 * emitting its locally authenticated fatal Alert. */
			const int client = conn->ctx && conn->ctx->is_client;
			const BLOCK_CIPHER_KEY *write_key =
				client ? &conn->client_write_key : &conn->server_write_key;
			const uint8_t *write_iv =
				client ? conn->client_write_iv : conn->server_write_iv;
			uint8_t *write_seq =
				client ? conn->client_seq_num : conn->server_seq_num;
			tls13_padding_len_rand(&padding_len);
			if (tls13_record_encrypt(conn->cipher_suite, write_key, write_iv,
				write_seq, conn->plain_record, conn->plain_recordlen, padding_len,
				conn->record, &conn->recordlen) != 1) {
				error_print();
				return -1;
			}
			tls_seq_num_incr(write_seq);
			break;
		}
		}
]==]
)

unset(_gmssl_tls13_fatal_alert_c)
