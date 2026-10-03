# Standard TLS signature-algorithm capacity/range contract.

set(_gmssl_tls_h "${SOURCE_PATH}/include/gmssl/tls.h")
set(_gmssl_tls_c "${SOURCE_PATH}/src/tls.c")

gmssl_replace_once(
    "${_gmssl_tls_h}"
[==[
	int signature_algorithms[2];
	size_t signature_algorithms_cnt;
]==]
[==[
	int signature_algorithms[8];
	size_t signature_algorithms_cnt;
]==]
)

gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	if (sig_algs_cnt > sizeof(ctx->signature_algorithms)/sizeof(ctx->signature_algorithms[0])) {
		error_print();
		return -1;
	}

	switch (ctx->protocol) {
]==]
[==[
	if (sig_algs_cnt > sizeof(ctx->signature_algorithms)/sizeof(ctx->signature_algorithms[0])) {
		error_print();
		return -1;
	}
	if (ctx->min_protocol == TLS_protocol_tls12
		&& ctx->max_protocol == TLS_protocol_tls13) {
		for (i = 0; i < sig_algs_cnt; i++) {
			if (!tls_type_is_in_list(sig_algs[i],
					tls13_signature_algorithms, tls13_signature_algorithms_cnt)
				&& !tls_type_is_in_list(sig_algs[i],
					tls12_signature_algorithms, tls12_signature_algorithms_cnt)) {
				error_print();
				return -1;
			}
		}
		memcpy(ctx->signature_algorithms, sig_algs,
			sig_algs_cnt * sizeof(sig_algs[0]));
		ctx->signature_algorithms_cnt = sig_algs_cnt;
		return 1;
	}

	switch (ctx->protocol) {
]==]
)

# tls_ctx_check() must validate the same TLS 1.2/1.3 union accepted by
# tls_ctx_set_signature_algorithms() for a standard version-range context.
gmssl_replace_once(
    "${_gmssl_tls_c}"
[==[
	for (i = 0; i < ctx->signature_algorithms_cnt; i++) {
		if (!tls_type_is_in_list(ctx->signature_algorithms[i],
			supported_sig_algs, supported_sig_algs_cnt)) {
			error_print();
			return -1;
		}
	}
]==]
[==[
	for (i = 0; i < ctx->signature_algorithms_cnt; i++) {
		if (standard_tls_range) {
			if (!tls_type_is_in_list(ctx->signature_algorithms[i],
					tls13_signature_algorithms, tls13_signature_algorithms_cnt)
				&& !tls_type_is_in_list(ctx->signature_algorithms[i],
					tls12_signature_algorithms, tls12_signature_algorithms_cnt)) {
				error_print();
				return -1;
			}
		} else if (!tls_type_is_in_list(ctx->signature_algorithms[i],
				supported_sig_algs, supported_sig_algs_cnt)) {
			error_print();
			return -1;
		}
	}
]==]
)

unset(_gmssl_tls_h)
unset(_gmssl_tls_c)
