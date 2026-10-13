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

unset(_gmssl_tls13_fatal_alert_c)
