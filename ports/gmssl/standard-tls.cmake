# Standard TLS compatibility adaptations required by Salts/CNet.
# Keep each adaptation narrow and independently testable.

set(_gmssl_tls12_c "${SOURCE_PATH}/src/tls12.c")

# TLS 1.2 client: advertise configured ALPN protocols in ClientHello.
vcpkg_replace_string(
    "${_gmssl_tls12_c}"
    "        // renegotiation_info\n        if (conn->ctx->renegotiation_info) {"
    "        // application_layer_protocol_negotiation\n        if (conn->ctx->alpn_protocols_cnt) {\n            if (tls_application_layer_protocol_negotiation_ext_to_bytes(\n                conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt,\n                &pexts, &extslen) != 1) {\n                error_print();\n                return -1;\n            }\n        }\n\n        // renegotiation_info\n        if (conn->ctx->renegotiation_info) {"
)

# TLS 1.2 client: retain the server-selected ALPN protocol from ServerHello.
vcpkg_replace_string(
    "${_gmssl_tls12_c}"
    "    int trusted_ca_keys = 0;\n    int renegotiation_info = 0;"
    "    int trusted_ca_keys = 0;\n    const uint8_t *application_layer_protocol_negotiation = NULL;\n    size_t application_layer_protocol_negotiation_len = 0;\n    int renegotiation_info = 0;"
)
vcpkg_replace_string(
    "${_gmssl_tls12_c}"
    "        case TLS_extension_ec_point_formats:\n            if (ec_point_formats) {"
    "        case TLS_extension_application_layer_protocol_negotiation:\n            if (!ext_data || application_layer_protocol_negotiation) {\n                error_print();\n                tls_send_alert(conn, TLS_alert_illegal_parameter);\n                return -1;\n            }\n            application_layer_protocol_negotiation = ext_data;\n            application_layer_protocol_negotiation_len = ext_datalen;\n            break;\n        case TLS_extension_ec_point_formats:\n            if (ec_point_formats) {"
    COUNT 1
)
vcpkg_replace_string(
    "${_gmssl_tls12_c}"
    "    if ((conn->ctx->renegotiation_info || conn->ctx->empty_renegotiation_info_scsv)"
    "    if (application_layer_protocol_negotiation) {\n        if (!conn->ctx->alpn_protocols_cnt ||\n            tls_application_layer_protocol_negotiation_selected_from_bytes(\n                &conn->alpn_selected,\n                application_layer_protocol_negotiation, application_layer_protocol_negotiation_len,\n                conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt) != 1) {\n            error_print();\n            tls_send_alert(conn, TLS_alert_illegal_parameter);\n            return -1;\n        }\n        conn->application_layer_protocol_negotiation = 1;\n    }\n\n    if ((conn->ctx->renegotiation_info || conn->ctx->empty_renegotiation_info_scsv)"
    COUNT 1
)

# TLS 1.2 server: parse the client's ALPN offer and select one local protocol.
vcpkg_replace_string(
    "${_gmssl_tls12_c}"
    "    const uint8_t *renegotiation_info = NULL;\n    size_t renegotiation_info_len = 0;"
    "    const uint8_t *application_layer_protocol_negotiation = NULL;\n    size_t application_layer_protocol_negotiation_len = 0;\n    const uint8_t *renegotiation_info = NULL;\n    size_t renegotiation_info_len = 0;"
)
vcpkg_replace_string(
    "${_gmssl_tls12_c}"
    "        case TLS_extension_renegotiation_info:\n            if (renegotiation_info) {"
    "        case TLS_extension_application_layer_protocol_negotiation:\n            if (!ext_data || application_layer_protocol_negotiation) {\n                error_print();\n                tls_send_alert(conn, TLS_alert_illegal_parameter);\n                return -1;\n            }\n            application_layer_protocol_negotiation = ext_data;\n            application_layer_protocol_negotiation_len = ext_datalen;\n            break;\n        case TLS_extension_renegotiation_info:\n            if (renegotiation_info) {"
    COUNT 1
)
vcpkg_replace_string(
    "${_gmssl_tls12_c}"
    "    if (server_name) {\n        if (tls_server_name_from_bytes(&host_name, &host_name_len, server_name, server_name_len) != 1) {"
    "    if (application_layer_protocol_negotiation) {\n        if (!conn->ctx->alpn_protocols_cnt) {\n            error_print();\n            tls_send_alert(conn, TLS_alert_no_application_protocol);\n            return -1;\n        }\n        if ((ret = tls_application_layer_protocol_negotiation_select(\n                application_layer_protocol_negotiation, application_layer_protocol_negotiation_len,\n                conn->ctx->alpn_protocols, conn->ctx->alpn_protocols_cnt,\n                &conn->alpn_selected)) != 1) {\n            error_print();\n            tls_send_alert(conn, TLS_alert_no_application_protocol);\n            return -1;\n        }\n        conn->application_layer_protocol_negotiation = 1;\n    }\n\n    if (server_name) {\n        if (tls_server_name_from_bytes(&host_name, &host_name_len, server_name, server_name_len) != 1) {"
    COUNT 1
)

# TLS 1.2 server: return the selected ALPN protocol in ServerHello.
vcpkg_replace_string(
    "${_gmssl_tls12_c}"
    "        // renegotiation_info\n        if (conn->secure_renegotiation) {"
    "        // application_layer_protocol_negotiation\n        if (conn->alpn_selected) {\n            if (tls_application_layer_protocol_negotiation_selected_ext_to_bytes(\n                    conn->alpn_selected, &pexts, &extslen) != 1) {\n                error_print();\n                return -1;\n            }\n        }\n\n        // renegotiation_info\n        if (conn->secure_renegotiation) {"
    COUNT 1
)
