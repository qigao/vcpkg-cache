# Crypto-owned post-import hardening. Do not edit the frozen 92 imported source
# blobs or change the 40 attested GmSSL 3.2.0#13 original transformations.
# All substitutions fail closed on source drift or ambiguous anchors.

function(crypto_gmssl_harden_once filename original fixed)
  if(NOT EXISTS "${filename}" OR "${original}" STREQUAL "")
    message(FATAL_ERROR "Invalid crypto source-hardening input: ${filename}")
  endif()
  set(_expected 1)
  if(ARGC EQUAL 4)
    set(_expected "${ARGV3}")
  elseif(NOT ARGC EQUAL 3)
    message(FATAL_ERROR "Invalid source hardening call arity")
  endif()
  file(READ "${filename}" _before)
  string(LENGTH "${original}" _length)
  set(_remainder "${_before}")
  set(_found 0)
  while(TRUE)
    string(FIND "${_remainder}" "${original}" _at)
    if(_at EQUAL -1)
      break()
    endif()
    math(EXPR _found "${_found} + 1")
    math(EXPR _after_offset "${_at} + ${_length}")
    string(SUBSTRING "${_remainder}" ${_after_offset} -1 _remainder)
  endwhile()
  if(NOT _found EQUAL _expected)
    message(FATAL_ERROR
      "Crypto hardening expected ${_expected} source anchors but found ${_found}: ${filename}")
  endif()
  string(REPLACE "${original}" "${fixed}" _after "${_before}")
  if("${_after}" STREQUAL "${_before}")
    message(FATAL_ERROR "Crypto hardening produced no source edit: ${filename}")
  endif()
  file(WRITE "${filename}" "${_after}")
endfunction()

# bn_add() returns an int carry bit. Signed (c & 1) << 31 has undefined
# behavior when c == 1. Cast the bit to a uint32_t before shifting to the
# high bit of the unsigned limb; the mathematical field operation is unchanged.
crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/secp256r1.c"
  [==[r[7] = (r[7] >> 1) | ((c & 1) << 31);]==]
  [==[r[7] = (r[7] >> 1) | ((uint32_t)(c & 1) << 31);]==])

crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/secp384r1.c"
  [==[r[11] = (r[11] >> 1) | ((c & 1) << 31);]==]
  [==[r[11] = (r[11] >> 1) | ((uint32_t)(c & 1) << 31);]==])

# TLS 1.2 ServerHello may contain a zero-length legacy session ID. The
# decoder's data pointer may legitimately be NULL for the empty vector.
# Never pass NULL to memcpy (even with size 0); also reject oversized IDs
# before copying to conn->session_id[32].
crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/tls12.c"
  [==[	// session_id
	memcpy(conn->session_id, session_id, session_id_len);
	conn->session_id_len = session_id_len;]==]
  [==[	// session_id
	if (session_id_len > sizeof(conn->session_id)
		|| (session_id_len && !session_id)) {
		error_print();
		tls_send_alert(conn, TLS_alert_decode_error);
		return -1;
	}
	if (session_id_len) {
		memcpy(conn->session_id, session_id, session_id_len);
	}
	conn->session_id_len = session_id_len;]==])

# TLS 1.3 ServerHello is also allowed to return an empty legacy
# session_id_echo. The decoder can represent the zero-length vector as
# NULL; memcmp(NULL, ..., 0) is undefined. Reject mismatched lengths or
# invalid nonempty pointers, and compare bytes only for a nonempty echo.
crypto_gmssl_harden_once(
  "${SOURCE_PATH}/src/tls13.c"
  [==[	// legacy_session_id_echo
	if (legacy_session_id_echo_len != conn->session_id_len
		|| memcmp(legacy_session_id_echo, conn->session_id, conn->session_id_len) != 0) {]==]
  [==[	// legacy_session_id_echo
	if (conn->session_id_len > sizeof(conn->session_id)
		|| legacy_session_id_echo_len != conn->session_id_len
		|| (conn->session_id_len
			&& (!legacy_session_id_echo
				|| memcmp(legacy_session_id_echo, conn->session_id, conn->session_id_len) != 0))) {]==]
  2)

message(STATUS "Applied 5 Crypto-owned post-import UB hardening edits")
