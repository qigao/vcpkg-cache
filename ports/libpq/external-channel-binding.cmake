# External TLS channel binding for the no-SSL libpq profile.
#
# This is a narrow overlay extension for callers that own and verify TLS
# outside libpq. It does not make libpq own TLS, does not set ssl_in_use, and
# initially accepts only the RFC 5929 "tls-server-end-point" binding used by
# PostgreSQL SCRAM-SHA-256-PLUS.

function(libpq_replace_once path before after)
    file(READ "${path}" _libpq_content)
    string(FIND "${_libpq_content}" "${before}" _libpq_first)
    if(_libpq_first EQUAL -1)
        message(FATAL_ERROR "libpq overlay marker not found in ${path}")
    endif()

    string(LENGTH "${before}" _libpq_before_len)
    math(EXPR _libpq_tail_start "${_libpq_first} + ${_libpq_before_len}")
    string(SUBSTRING "${_libpq_content}" ${_libpq_tail_start} -1 _libpq_tail)
    string(FIND "${_libpq_tail}" "${before}" _libpq_second)
    if(NOT _libpq_second EQUAL -1)
        message(FATAL_ERROR "libpq overlay marker is not unique in ${path}")
    endif()

    string(REPLACE "${before}" "${after}" _libpq_content "${_libpq_content}")
    file(WRITE "${path}" "${_libpq_content}")
endfunction()

set(_libpq_fe_h "${SOURCE_PATH}/src/interfaces/libpq/libpq-fe.h")
set(_libpq_int_h "${SOURCE_PATH}/src/interfaces/libpq/libpq-int.h")
set(_libpq_connect_c "${SOURCE_PATH}/src/interfaces/libpq/fe-connect.c")
set(_libpq_auth_c "${SOURCE_PATH}/src/interfaces/libpq/fe-auth.c")
set(_libpq_scram_c "${SOURCE_PATH}/src/interfaces/libpq/fe-auth-scram.c")
set(_libpq_exports "${SOURCE_PATH}/src/interfaces/libpq/exports.txt")

libpq_replace_once(
    "${_libpq_fe_h}"
[==[
#define LIBPQ_HAS_SSL_LIBRARY_DETECTION 1
]==]
[==[
#define LIBPQ_HAS_SSL_LIBRARY_DETECTION 1
/* Indicates presence of PQsetExternalChannelBinding */
#define LIBPQ_HAS_EXTERNAL_CHANNEL_BINDING 1
]==]
)

libpq_replace_once(
    "${_libpq_fe_h}"
[==[
extern PostgresPollingStatusType PQconnectPoll(PGconn *conn);

/* Synchronous (blocking) */
]==]
[==[
extern PostgresPollingStatusType PQconnectPoll(PGconn *conn);

/*
 * Install copied RFC 5929 channel-binding bytes supplied by an externally
 * verified TLS owner. Currently only "tls-server-end-point" is accepted.
 * This must be called before SASL authentication starts and with
 * sslmode=disable. Returns 1 on success, 0 on error.
 */
extern int	PQsetExternalChannelBinding(PGconn *conn, const char *type,
										const void *data, size_t len);

/* Synchronous (blocking) */
]==]
)

libpq_replace_once(
    "${_libpq_int_h}"
[==[
	const pg_fe_sasl_mech *sasl;
	void	   *sasl_state;
	int			scram_sha_256_iterations;

	/* SSL structures */
]==]
[==[
	const pg_fe_sasl_mech *sasl;
	void	   *sasl_state;
	int			scram_sha_256_iterations;

	/*
	 * Copied RFC 5929 channel binding supplied by an external TLS owner.
	 * PGconn is opaque to applications, so this remains private libpq state.
	 */
	unsigned char external_channel_binding[64];
	size_t		external_channel_binding_len;
	bool		external_channel_binding_locked;

	/* SSL structures */
]==]
)

libpq_replace_once(
    "${_libpq_connect_c}"
[==[
	if (conn->sasl_state)
	{
		conn->sasl->free(conn->sasl_state);
		conn->sasl_state = NULL;
	}
}
]==]
[==[
	if (conn->sasl_state)
	{
		conn->sasl->free(conn->sasl_state);
		conn->sasl_state = NULL;
	}

	/*
	 * An external binding belongs to exactly one physical transport session.
	 * Never carry it across connection teardown, address retry, or PQreset().
	 */
	explicit_bzero(conn->external_channel_binding,
				   sizeof(conn->external_channel_binding));
	conn->external_channel_binding_len = 0;
	conn->external_channel_binding_locked = false;
}
]==]
)

libpq_replace_once(
    "${_libpq_connect_c}"
[==[
	return conn;
}

/*
 *		PQconnectStart
]==]
[==[
	return conn;
}

/*
 * PQsetExternalChannelBinding
 *
 * Install copied channel-binding bytes for an externally owned and verified
 * TLS session. This intentionally does not alter ssl_in_use or any native TLS
 * state. The current extension is deliberately narrow: PostgreSQL SCRAM PLUS
 * uses only RFC 5929 tls-server-end-point.
 */
int
PQsetExternalChannelBinding(PGconn *conn, const char *type,
							const void *data, size_t len)
{
	if (conn == NULL)
		return 0;

	if (type == NULL || strcmp(type, "tls-server-end-point") != 0)
	{
		libpq_append_conn_error(conn,
							 "unsupported external channel binding type");
		return 0;
	}
	if (data == NULL || len == 0 ||
		len > sizeof(conn->external_channel_binding))
	{
		libpq_append_conn_error(conn,
							 "invalid external channel binding data");
		return 0;
	}
	if (conn->external_channel_binding_locked ||
		conn->sasl_state != NULL ||
		conn->client_finished_auth ||
		conn->status == CONNECTION_AUTH_OK ||
		conn->status == CONNECTION_OK)
	{
		libpq_append_conn_error(conn,
							 "external channel binding must be installed before authentication starts");
		return 0;
	}
	if (conn->sslmode == NULL || strcmp(conn->sslmode, "disable") != 0)
	{
		libpq_append_conn_error(conn,
							 "external channel binding requires sslmode=disable");
		return 0;
	}

	explicit_bzero(conn->external_channel_binding,
				   sizeof(conn->external_channel_binding));
	memcpy(conn->external_channel_binding, data, len);
	conn->external_channel_binding_len = len;
	return 1;
}

/*
 *		PQconnectStart
]==]
)

libpq_replace_once(
    "${_libpq_auth_c}"
[==[
	initPQExpBuffer(&mechanism_buf);

	if (conn->channel_binding[0] == 'r' &&	/* require */
		!conn->ssl_in_use)
	{
		libpq_append_conn_error(conn, "channel binding required, but SSL not in use");
		goto error;
	}
]==]
[==[
	initPQExpBuffer(&mechanism_buf);

	/* The external binding can no longer be replaced once SASL is observed. */
	conn->external_channel_binding_locked = true;

	if (conn->channel_binding[0] == 'r' &&	/* require */
		!conn->ssl_in_use &&
		conn->external_channel_binding_len == 0)
	{
		libpq_append_conn_error(conn,
							 "channel binding required, but no usable channel binding is available");
		goto error;
	}
]==]
)

libpq_replace_once(
    "${_libpq_auth_c}"
[==[
		if (strcmp(mechanism_buf.data, SCRAM_SHA_256_PLUS_NAME) == 0)
		{
			if (conn->ssl_in_use)
			{
				/* The server has offered SCRAM-SHA-256-PLUS. */

#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
				/*
				 * The client supports channel binding, which is chosen if
				 * channel_binding is not disabled.
				 */
				if (conn->channel_binding[0] != 'd')	/* disable */
				{
					selected_mechanism = SCRAM_SHA_256_PLUS_NAME;
					conn->sasl = &pg_scram_mech;
				}
#else
				/*
				 * The client does not support channel binding.  If it is
				 * required, complain immediately instead of the error below
				 * which would be confusing as the server is publishing
				 * SCRAM-SHA-256-PLUS.
				 */
				if (conn->channel_binding[0] == 'r')	/* require */
				{
					libpq_append_conn_error(conn, "channel binding is required, but client does not support it");
					goto error;
				}
#endif
			}
			else
			{
				/*
				 * The server offered SCRAM-SHA-256-PLUS, but the connection
				 * is not SSL-encrypted. That's not sane. Perhaps SSL was
				 * stripped by a proxy? There's no point in continuing,
				 * because the server will reject the connection anyway if we
				 * try authenticate without channel binding even though both
				 * the client and server supported it. The SCRAM exchange
				 * checks for that, to prevent downgrade attacks.
				 */
				libpq_append_conn_error(conn, "server offered SCRAM-SHA-256-PLUS authentication over a non-SSL connection");
				goto error;
			}
		}
]==]
[==[
		if (strcmp(mechanism_buf.data, SCRAM_SHA_256_PLUS_NAME) == 0)
		{
			if (conn->external_channel_binding_len > 0)
			{
				/*
				 * External TLS has already been verified by the owner. Pick
				 * PLUS only when channel binding policy has not disabled it.
				 */
				if (conn->channel_binding[0] != 'd')	/* disable */
				{
					selected_mechanism = SCRAM_SHA_256_PLUS_NAME;
					conn->sasl = &pg_scram_mech;
				}
			}
			else if (conn->ssl_in_use)
			{
				/* The server has offered SCRAM-SHA-256-PLUS. */

#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
				/*
				 * Native libpq TLS supports channel binding, which is chosen
				 * if channel_binding is not disabled.
				 */
				if (conn->channel_binding[0] != 'd')	/* disable */
				{
					selected_mechanism = SCRAM_SHA_256_PLUS_NAME;
					conn->sasl = &pg_scram_mech;
				}
#else
				if (conn->channel_binding[0] == 'r')	/* require */
				{
					libpq_append_conn_error(conn, "channel binding is required, but client does not support it");
					goto error;
				}
#endif
			}
			else
			{
				/*
				 * Preserve the existing fail-closed downgrade behavior when
				 * neither native TLS nor an external verified binding exists.
				 */
				libpq_append_conn_error(conn, "server offered SCRAM-SHA-256-PLUS authentication without usable channel binding");
				goto error;
			}
		}
]==]
)

libpq_replace_once(
    "${_libpq_scram_c}"
[==[
	if (strcmp(state->sasl_mechanism, SCRAM_SHA_256_PLUS_NAME) == 0)
	{
		Assert(conn->ssl_in_use);
		appendPQExpBufferStr(&buf, "p=tls-server-end-point");
	}
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
	else if (conn->channel_binding[0] != 'd' && /* disable */
			 conn->ssl_in_use)
	{
		/*
		 * Client supports channel binding, but thinks the server does not.
		 */
		appendPQExpBufferChar(&buf, 'y');
	}
#endif
	else
]==]
[==[
	if (strcmp(state->sasl_mechanism, SCRAM_SHA_256_PLUS_NAME) == 0)
	{
		Assert(conn->ssl_in_use || conn->external_channel_binding_len > 0);
		appendPQExpBufferStr(&buf, "p=tls-server-end-point");
	}
	else if (conn->channel_binding[0] != 'd' && /* disable */
			 (conn->external_channel_binding_len > 0
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
			  || conn->ssl_in_use
#endif
			 ))
	{
		/*
		 * Client supports channel binding, but thinks the server does not.
		 */
		appendPQExpBufferChar(&buf, 'y');
	}
	else
]==]
)

libpq_replace_once(
    "${_libpq_scram_c}"
[==[
	if (strcmp(state->sasl_mechanism, SCRAM_SHA_256_PLUS_NAME) == 0)
	{
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
		char	   *cbind_data = NULL;
		size_t		cbind_data_len = 0;
		size_t		cbind_header_len;
		char	   *cbind_input;
		size_t		cbind_input_len;
		int			encoded_cbind_len;

		/* Fetch hash data of server's SSL certificate */
		cbind_data =
			pgtls_get_peer_certificate_hash(state->conn,
											&cbind_data_len);
		if (cbind_data == NULL)
		{
			/* error message is already set on error */
			termPQExpBuffer(&buf);
			return NULL;
		}

		appendPQExpBufferStr(&buf, "c=");

		/* p=type,, */
		cbind_header_len = strlen("p=tls-server-end-point,,");
		cbind_input_len = cbind_header_len + cbind_data_len;
		cbind_input = malloc(cbind_input_len);
		if (!cbind_input)
		{
			free(cbind_data);
			goto oom_error;
		}
		memcpy(cbind_input, "p=tls-server-end-point,,", cbind_header_len);
		memcpy(cbind_input + cbind_header_len, cbind_data, cbind_data_len);

		encoded_cbind_len = pg_b64_enc_len(cbind_input_len);
		if (!enlargePQExpBuffer(&buf, encoded_cbind_len))
		{
			free(cbind_data);
			free(cbind_input);
			goto oom_error;
		}
		encoded_cbind_len = pg_b64_encode(cbind_input, cbind_input_len,
										  buf.data + buf.len,
										  encoded_cbind_len);
		if (encoded_cbind_len < 0)
		{
			free(cbind_data);
			free(cbind_input);
			termPQExpBuffer(&buf);
			appendPQExpBufferStr(&conn->errorMessage,
								 "could not encode cbind data for channel binding\n");
			return NULL;
		}
		buf.len += encoded_cbind_len;
		buf.data[buf.len] = '\0';

		free(cbind_data);
		free(cbind_input);
#else
		/*
		 * Chose channel binding, but the SSL library doesn't support it.
		 * Shouldn't happen.
		 */
		termPQExpBuffer(&buf);
		appendPQExpBufferStr(&conn->errorMessage,
							 "channel binding not supported by this build\n");
		return NULL;
#endif							/* HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH */
	}
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
	else if (conn->channel_binding[0] != 'd' && /* disable */
			 conn->ssl_in_use)
		appendPQExpBufferStr(&buf, "c=eSws");	/* base64 of "y,," */
#endif
	else
]==]
[==[
	if (strcmp(state->sasl_mechanism, SCRAM_SHA_256_PLUS_NAME) == 0)
	{
		const char *cbind_data =
			(const char *) conn->external_channel_binding;
		size_t		cbind_data_len = conn->external_channel_binding_len;
		char	   *native_cbind_data = NULL;
		size_t		cbind_header_len;
		char	   *cbind_input;
		size_t		cbind_input_len;
		int			encoded_cbind_len;

		if (cbind_data_len == 0)
		{
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
			native_cbind_data =
				pgtls_get_peer_certificate_hash(state->conn,
												&cbind_data_len);
			if (native_cbind_data == NULL)
			{
				/* error message is already set on error */
				termPQExpBuffer(&buf);
				return NULL;
			}
			cbind_data = native_cbind_data;
#else
			termPQExpBuffer(&buf);
			appendPQExpBufferStr(&conn->errorMessage,
								 "channel binding not supported by this build\n");
			return NULL;
#endif
		}

		appendPQExpBufferStr(&buf, "c=");

		/* p=type,, */
		cbind_header_len = strlen("p=tls-server-end-point,,");
		cbind_input_len = cbind_header_len + cbind_data_len;
		cbind_input = malloc(cbind_input_len);
		if (!cbind_input)
		{
			free(native_cbind_data);
			goto oom_error;
		}
		memcpy(cbind_input, "p=tls-server-end-point,,", cbind_header_len);
		memcpy(cbind_input + cbind_header_len, cbind_data, cbind_data_len);

		encoded_cbind_len = pg_b64_enc_len(cbind_input_len);
		if (!enlargePQExpBuffer(&buf, encoded_cbind_len))
		{
			free(native_cbind_data);
			free(cbind_input);
			goto oom_error;
		}
		encoded_cbind_len = pg_b64_encode(cbind_input, cbind_input_len,
										  buf.data + buf.len,
										  encoded_cbind_len);
		if (encoded_cbind_len < 0)
		{
			free(native_cbind_data);
			free(cbind_input);
			termPQExpBuffer(&buf);
			appendPQExpBufferStr(&conn->errorMessage,
								 "could not encode cbind data for channel binding\n");
			return NULL;
		}
		buf.len += encoded_cbind_len;
		buf.data[buf.len] = '\0';

		free(native_cbind_data);
		free(cbind_input);
	}
	else if (conn->channel_binding[0] != 'd' && /* disable */
			 (conn->external_channel_binding_len > 0
#ifdef HAVE_PGTLS_GET_PEER_CERTIFICATE_HASH
			  || conn->ssl_in_use
#endif
			 ))
		appendPQExpBufferStr(&buf, "c=eSws");	/* base64 of "y,," */
	else
]==]
)

libpq_replace_once(
    "${_libpq_exports}"
[==[
PQconnectionUsedGSSAPI    187
]==]
[==[
PQconnectionUsedGSSAPI    187
PQsetExternalChannelBinding 188
]==]
)

unset(_libpq_fe_h)
unset(_libpq_int_h)
unset(_libpq_connect_c)
unset(_libpq_auth_c)
unset(_libpq_scram_c)
unset(_libpq_exports)
