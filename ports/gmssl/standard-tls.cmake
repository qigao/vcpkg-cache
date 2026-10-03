# Standard TLS compatibility adaptations required by Salts/CNet.
# Keep each adaptation narrow and independently testable.

set(_gmssl_tls12_c "${SOURCE_PATH}/src/tls12.c")

function(gmssl_replace_once file_path search_text replacement_text)
    file(READ "${file_path}" _gmssl_replace_content)
    string(FIND "${_gmssl_replace_content}" "${search_text}" _gmssl_replace_offset)
    if(_gmssl_replace_offset EQUAL -1)
        message(FATAL_ERROR "GmSSL standard-TLS adaptation anchor not found in ${file_path}")
    endif()
    string(LENGTH "${search_text}" _gmssl_replace_length)
    string(SUBSTRING "${_gmssl_replace_content}" 0 ${_gmssl_replace_offset} _gmssl_replace_prefix)
    math(EXPR _gmssl_replace_suffix_offset "${_gmssl_replace_offset} + ${_gmssl_replace_length}")
    string(SUBSTRING "${_gmssl_replace_content}" ${_gmssl_replace_suffix_offset} -1 _gmssl_replace_suffix)
    file(WRITE "${file_path}" "${_gmssl_replace_prefix}${replacement_text}${_gmssl_replace_suffix}")
endfunction()

# TLS 1.2 client: advertise configured ALPN protocols in ClientHello.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		// renegotiation_info
		if (conn->ctx->renegotiation_info) {
]==]
[==[
		// application_layer_protocol_negotiation
		if (conn->ctx->alpn_protocols_cnt) {
			if (tls_application_layer_protocol_negotiation_ext_to_bytes(
				conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt,
				&pexts, &extslen) != 1) {
				error_print();
				return -1;
			}
		}

		// renegotiation_info
		if (conn->ctx->renegotiation_info) {
]==]
)

# TLS 1.2 client: retain the server-selected ALPN protocol from ServerHello.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	int trusted_ca_keys = 0;
	int renegotiation_info = 0;
]==]
[==[
	int trusted_ca_keys = 0;
	const uint8_t *application_layer_protocol_negotiation = NULL;
	size_t application_layer_protocol_negotiation_len = 0;
	int renegotiation_info = 0;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		case TLS_extension_ec_point_formats:
			if (ec_point_formats) {
]==]
[==[
		case TLS_extension_application_layer_protocol_negotiation:
			if (!ext_data || application_layer_protocol_negotiation) {
				error_print();
				tls_send_alert(conn, TLS_alert_illegal_parameter);
				return -1;
			}
			application_layer_protocol_negotiation = ext_data;
			application_layer_protocol_negotiation_len = ext_datalen;
			break;
		case TLS_extension_ec_point_formats:
			if (ec_point_formats) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if ((conn->ctx->renegotiation_info || conn->ctx->empty_renegotiation_info_scsv)
]==]
[==[
	if (application_layer_protocol_negotiation) {
		if (!conn->ctx->alpn_protocols_cnt
			|| tls_application_layer_protocol_negotiation_selected_from_bytes(
				&conn->alpn_selected,
				application_layer_protocol_negotiation, application_layer_protocol_negotiation_len,
				conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt) != 1) {
			error_print();
			tls_send_alert(conn, TLS_alert_illegal_parameter);
			return -1;
		}
		conn->application_layer_protocol_negotiation = 1;
	}

	if ((conn->ctx->renegotiation_info || conn->ctx->empty_renegotiation_info_scsv)
]==]
)

# TLS 1.2 server: parse the client's ALPN offer and select one local protocol.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	const uint8_t *renegotiation_info = NULL;
	size_t renegotiation_info_len = 0;
]==]
[==[
	const uint8_t *application_layer_protocol_negotiation = NULL;
	size_t application_layer_protocol_negotiation_len = 0;
	const uint8_t *renegotiation_info = NULL;
	size_t renegotiation_info_len = 0;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		case TLS_extension_renegotiation_info:
			if (renegotiation_info) {
]==]
[==[
		case TLS_extension_application_layer_protocol_negotiation:
			if (!ext_data || application_layer_protocol_negotiation) {
				error_print();
				tls_send_alert(conn, TLS_alert_illegal_parameter);
				return -1;
			}
			application_layer_protocol_negotiation = ext_data;
			application_layer_protocol_negotiation_len = ext_datalen;
			break;
		case TLS_extension_renegotiation_info:
			if (renegotiation_info) {
]==]
)

gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
	if (server_name) {
		if (tls_server_name_from_bytes(&host_name, &host_name_len, server_name, server_name_len) != 1) {
]==]
[==[
	if (application_layer_protocol_negotiation) {
		if (!conn->ctx->alpn_protocols_cnt) {
			error_print();
			tls_send_alert(conn, TLS_alert_no_application_protocol);
			return -1;
		}
		if ((ret = tls_application_layer_protocol_negotiation_select(
			application_layer_protocol_negotiation, application_layer_protocol_negotiation_len,
			conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt,
			&conn->alpn_selected)) != 1) {
			error_print();
			tls_send_alert(conn, TLS_alert_no_application_protocol);
			return -1;
		}
		conn->application_layer_protocol_negotiation = 1;
	}

	if (server_name) {
		if (tls_server_name_from_bytes(&host_name, &host_name_len, server_name, server_name_len) != 1) {
]==]
)

# TLS 1.2 server: return the selected ALPN protocol in ServerHello.
gmssl_replace_once(
    "${_gmssl_tls12_c}"
[==[
		// renegotiation_info
		if (conn->secure_renegotiation) {
]==]
[==[
		// application_layer_protocol_negotiation
		if (conn->alpn_selected) {
			if (tls_application_layer_protocol_negotiation_selected_ext_to_bytes(
				conn->alpn_selected, &pexts, &extslen) != 1) {
				error_print();
				return -1;
			}
		}

		// renegotiation_info
		if (conn->secure_renegotiation) {
]==]
)

unset(_gmssl_tls12_c)

# TLS 1.3 client: CertificateRequest must ignore unknown extensions for
# forward compatibility. Keep all known extension validation strict.
set(_gmssl_tls13_c "${SOURCE_PATH}/src/tls13.c")
gmssl_replace_once(
    "${_gmssl_tls13_c}"
[==[
		case TLS_extension_signed_certificate_timestamp:
			if (signed_certificate_timestamp) {
				error_print();
				tls13_send_alert(conn, TLS_alert_illegal_parameter);
				return -1;
			}
			signed_certificate_timestamp = 1;
			break;

		default:
			error_print();
			tls13_send_alert(conn, TLS_alert_illegal_parameter);
			return -1;
		}
]==]
[==[
		case TLS_extension_signed_certificate_timestamp:
			if (signed_certificate_timestamp) {
				error_print();
				tls13_send_alert(conn, TLS_alert_illegal_parameter);
				return -1;
			}
			signed_certificate_timestamp = 1;
			break;

		default:
			/* RFC 8446 extension processing requires unknown extensions to be
			 * ignored. They do not participate in client-certificate selection. */
			break;
		}
]==]
)
file(READ "${_gmssl_tls13_c}" _gmssl_tls13_after)
string(FIND "${_gmssl_tls13_after}"
    "RFC 8446 extension processing requires unknown extensions to be"
    _gmssl_tls13_unknown_ext_offset)
if(_gmssl_tls13_unknown_ext_offset EQUAL -1)
    message(FATAL_ERROR "GmSSL TLS 1.3 CertificateRequest unknown-extension contract missing")
endif()
unset(_gmssl_tls13_unknown_ext_offset)
unset(_gmssl_tls13_after)
unset(_gmssl_tls13_c)

