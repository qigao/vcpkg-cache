# Encrypted TLS 1.3 handshake messages are independent of record boundaries.
set(_gmssl_tls13 "${SOURCE_PATH}/src/tls13.c")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/tls13-handshake-reader.h" DESTINATION "${SOURCE_PATH}/src")

gmssl_replace_once("${SOURCE_PATH}/include/gmssl/tls.h"
[==[
	uint8_t plain_record[TLS_MAX_RECORD_SIZE];]==]
[==[
	/* Owned by the handshake progress caller; bounded across nonblocking retries. */
	uint8_t handshake_fragment[TLS_MAX_RECORD_SIZE];
	size_t handshake_fragment_len;
	size_t handshake_fragment_offset;
	size_t handshake_message_len;
	int handshake_message_pending;
	uint8_t plain_record[TLS_MAX_RECORD_SIZE];]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_encrypted_extensions(TLS_CONNECT *conn)]==]
[==[

#include "tls13-handshake-reader.h"

int tls13_recv_encrypted_extensions(TLS_CONNECT *conn)]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_encrypted_extensions(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *exts;
	size_t extslen;

	const uint8_t *supported_groups = NULL;

	int server_name = 0;
	int early_data = 0;
	int alpn = 0;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv {EncryptedExtensions}\n");
	if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
		conn->server_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->server_seq_num);]==]
[==[
int tls13_recv_encrypted_extensions(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *exts;
	size_t extslen;

	const uint8_t *supported_groups = NULL;

	int server_name = 0;
	int early_data = 0;
	int alpn = 0;

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_certificate_request(TLS_CONNECT *conn)
{
	int ret;
	int handshake_type;
	const uint8_t *handshake_data;
	size_t handshake_datalen;
	int client_cert;

	// certificate_request
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *exts;
	size_t extslen;

	// extensions
	const uint8_t *signature_algorithms = NULL;
	size_t signature_algorithms_len;
	const uint8_t *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_len;
	const uint8_t *certificate_authorities = NULL;
	size_t certificate_authorities_len;
	const uint8_t *oid_filters = NULL;
	size_t oid_filters_len;
	int status_request = 0;
	int signed_certificate_timestamp = 0;

	int common_sig_algs[4];
	size_t common_sig_algs_cnt;
	int common_sig_algs_cert[4];
	size_t common_sig_algs_cert_cnt;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *filters = NULL;
	size_t filters_len = 0;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv {CertificateRequest*}\n");

	if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
		conn->server_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->server_seq_num);]==]
[==[
int tls13_recv_certificate_request(TLS_CONNECT *conn)
{
	int ret;
	int handshake_type;
	const uint8_t *handshake_data;
	size_t handshake_datalen;
	int client_cert;

	// certificate_request
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *exts;
	size_t extslen;

	// extensions
	const uint8_t *signature_algorithms = NULL;
	size_t signature_algorithms_len;
	const uint8_t *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_len;
	const uint8_t *certificate_authorities = NULL;
	size_t certificate_authorities_len;
	const uint8_t *oid_filters = NULL;
	size_t oid_filters_len;
	int status_request = 0;
	int signed_certificate_timestamp = 0;

	int common_sig_algs[4];
	size_t common_sig_algs_cnt;
	int common_sig_algs_cert[4];
	size_t common_sig_algs_cert_cnt;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *filters = NULL;
	size_t filters_len = 0;

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_server_certificate(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *leaf_status_request_ocsp_response = NULL;
	size_t leaf_status_request_ocsp_response_len = 0;
	const uint8_t *leaf_signed_certificate_timestamp;
	size_t leaf_signed_certificate_timestamp_len;
	const uint8_t *cert;
	size_t certlen;

	const int *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *host_name = NULL;
	size_t host_name_len = 0;

	int verify_result = X509_verify_ok;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv server {Certificate}\n");

	// decrypt unless previous handshake is CertificateRequest
	if (!conn->plain_recordlen) {
		if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
			conn->server_seq_num, conn->record, conn->recordlen,
			conn->plain_record, &conn->plain_recordlen) != 1) {
			error_print();
			tls13_send_alert(conn, TLS_alert_bad_record_mac);
			return -1;
		}
		tls_seq_num_incr(conn->server_seq_num);

	}]==]
[==[
int tls13_recv_server_certificate(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *leaf_status_request_ocsp_response = NULL;
	size_t leaf_status_request_ocsp_response_len = 0;
	const uint8_t *leaf_signed_certificate_timestamp;
	size_t leaf_signed_certificate_timestamp_len;
	const uint8_t *cert;
	size_t certlen;

	const int *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *host_name = NULL;
	size_t host_name_len = 0;

	int verify_result = X509_verify_ok;

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_server_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	int sig_alg;
	const uint8_t *sig;
	size_t siglen;
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv server {CertificateVerify}\n");

	if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
		conn->server_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->server_seq_num);]==]
[==[
int tls13_recv_server_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	int sig_alg;
	const uint8_t *sig;
	size_t siglen;
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_client_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	int sig_alg;
	const uint8_t *sig;
	size_t siglen;
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv client {CertificateVerify}\n");

	if (tls13_record_decrypt(conn->cipher_suite, &conn->client_write_key, conn->client_write_iv,
		conn->client_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->client_seq_num);]==]
[==[
int tls13_recv_client_certificate_verify(TLS_CONNECT *conn)
{
	int ret;
	int sig_alg;
	const uint8_t *sig;
	size_t siglen;
	const uint8_t *cert;
	size_t certlen;
	X509_KEY public_key;

	if ((ret = tls13_recv_handshake_message(conn, 0)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_server_finished(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *server_verify_data;
	size_t server_verify_data_len;
	uint8_t verify_data[64];
	size_t verify_data_len;

	// compute verify_data before digest_update
	if (tls13_compute_verify_data(conn->server_handshake_traffic_secret,
		&conn->dgst_ctx, verify_data, &verify_data_len) != 1) {
		error_print();
		return -1;
	}

	if (!conn->plain_recordlen) {

		if ((ret = tls_recv_record(conn)) != 1) {
			if (ret != TLS_ERROR_RECV_AGAIN) {
				error_print();
			}
			return ret;
		}

		if (tls13_record_decrypt(conn->cipher_suite, &conn->server_write_key, conn->server_write_iv,
			conn->server_seq_num, conn->record, conn->recordlen,
			conn->plain_record, &conn->plain_recordlen) != 1) {
			error_print();
			tls13_send_alert(conn, TLS_alert_bad_record_mac);
			return -1;
		}
		tls_seq_num_incr(conn->server_seq_num);
	}]==]
[==[
int tls13_recv_server_finished(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *server_verify_data;
	size_t server_verify_data_len;
	uint8_t verify_data[64];
	size_t verify_data_len;

	// compute verify_data before digest_update
	if (tls13_compute_verify_data(conn->server_handshake_traffic_secret,
		&conn->dgst_ctx, verify_data, &verify_data_len) != 1) {
		error_print();
		return -1;
	}

	if ((ret = tls13_recv_handshake_message(conn, 1)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_client_certificate(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *status_request_ocsp_response = NULL;
	size_t status_request_ocsp_response_len = 0;
	const uint8_t *signed_certificate_timestamp = NULL;
	size_t signed_certificate_timestamp_len;
	const uint8_t *cert;
	size_t certlen;

	const int *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *oid_filters = NULL;
	size_t oid_filters_len = 0;

	int verify_result = X509_verify_ok;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv client {Certificate*}\n");

	if (tls_record_protocol(conn->record) != TLS_protocol_tls12) {
		error_print();
		tls13_send_alert(conn, TLS_alert_protocol_version);
		return -1;
	}

	//format_print(stderr, 0, 0, "client_seq_num: "PRIu64"\n", GETU64(conn->client_seq_num));

	if (tls13_record_decrypt(conn->cipher_suite, &conn->client_write_key, conn->client_write_iv,
		conn->client_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->client_seq_num);]==]
[==[
int tls13_recv_client_certificate(TLS_CONNECT *conn)
{
	int ret;
	const uint8_t *request_context;
	size_t request_context_len;
	const uint8_t *status_request_ocsp_response = NULL;
	size_t status_request_ocsp_response_len = 0;
	const uint8_t *signed_certificate_timestamp = NULL;
	size_t signed_certificate_timestamp_len;
	const uint8_t *cert;
	size_t certlen;

	const int *signature_algorithms_cert = NULL;
	size_t signature_algorithms_cert_cnt = 0;
	const uint8_t *ca_names = NULL;
	size_t ca_names_len = 0;
	const uint8_t *oid_filters = NULL;
	size_t oid_filters_len = 0;

	int verify_result = X509_verify_ok;

	if ((ret = tls13_recv_handshake_message(conn, 0)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
int tls13_recv_client_finished(TLS_CONNECT *conn)
{
	int ret;

	// Finished
	uint8_t local_verify_data[64];
	size_t local_verify_data_len;
	const uint8_t *verify_data;
	size_t verify_data_len;

	if ((ret = tls_recv_record(conn)) != 1) {
		if (ret != TLS_ERROR_RECV_AGAIN) {
			error_print();
		}
		return ret;
	}
	if(conn->verbose) tls_trace("recv client {Finished}\n");

	if (tls_record_protocol(conn->record) != TLS_protocol_tls12) {
		error_print();
		tls13_send_alert(conn, TLS_alert_protocol_version);
		return -1;
	}

	//format_print(stderr, 0, 0, "client_seq_num: "PRIu64"\n", GETU64(conn->client_seq_num));

	if (tls13_record_decrypt(conn->cipher_suite, &conn->client_write_key, conn->client_write_iv,
		conn->client_seq_num, conn->record, conn->recordlen,
		conn->plain_record, &conn->plain_recordlen) != 1) {
		error_print();
		tls13_send_alert(conn, TLS_alert_bad_record_mac);
		return -1;
	}
	tls_seq_num_incr(conn->client_seq_num);]==]
[==[
int tls13_recv_client_finished(TLS_CONNECT *conn)
{
	int ret;

	// Finished
	uint8_t local_verify_data[64];
	size_t local_verify_data_len;
	const uint8_t *verify_data;
	size_t verify_data_len;

	if ((ret = tls13_recv_handshake_message(conn, 0)) != 1) {
		return ret;
	}]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
	if (handshake_type != TLS_handshake_certificate_request) {]==]
[==[
	if (handshake_type != TLS_handshake_certificate_request) {
		conn->handshake_message_pending = 1;]==])

gmssl_replace_once("${_gmssl_tls13}"
[==[
static int tls13_recv_change_cipher_spec_if_present(TLS_CONNECT *conn)
{
	int ret;]==]
[==[
static int tls13_recv_change_cipher_spec_if_present(TLS_CONNECT *conn)
{
	int ret;

	/* A coalesced next handshake already rules out an intervening CCS. */
	if (conn->handshake_fragment_offset < conn->handshake_fragment_len) return 0;]==])

unset(_gmssl_tls13)
