# Absent optional extensions must pass an empty value/count pair to certificate
# selection. MSVC runtime checks catch these reads on ordinary IP/mTLS peers.
gmssl_replace_once("${SOURCE_PATH}/src/tls13.c"
  "\tint client_cert;" "\tint client_cert = 0;")
gmssl_replace_once("${SOURCE_PATH}/src/tls13.c"
  "\tsize_t common_sig_algs_cert_cnt;" "\tsize_t common_sig_algs_cert_cnt = 0;")
gmssl_replace_once("${SOURCE_PATH}/src/tls13.c"
  "\tsize_t host_name_len;" "\tsize_t host_name_len = 0;")
