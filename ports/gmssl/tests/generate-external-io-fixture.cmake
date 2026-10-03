if(NOT DEFINED GMSSL_CLI OR NOT EXISTS "${GMSSL_CLI}")
  message(FATAL_ERROR "GMSSL_CLI is required")
endif()
if(NOT DEFINED OUT_DIR)
  message(FATAL_ERROR "OUT_DIR is required")
endif()

file(MAKE_DIRECTORY "${OUT_DIR}")
set(_pass "P@ssw0rd")

function(gmssl_run)
  execute_process(
    COMMAND "${GMSSL_CLI}" ${ARGN}
    WORKING_DIRECTORY "${OUT_DIR}"
    RESULT_VARIABLE _rc
    OUTPUT_VARIABLE _out
    ERROR_VARIABLE _err
  )
  if(NOT _rc EQUAL 0)
    message(FATAL_ERROR "gmssl command failed (${_rc}): ${ARGN}\nstdout:\n${_out}\nstderr:\n${_err}")
  endif()
endfunction()

gmssl_run(p256keygen -pass ${_pass} -out ca-key.pem)
gmssl_run(certgen
  -C CN -ST Beijing -L Haidian -O GmSSL -OU ExternalIO
  -CN "GmSSL External IO Root"
  -days 2
  -key ca-key.pem
  -pass ${_pass}
  -out ca-cert.pem
  -key_usage keyCertSign
  -key_usage cRLSign
  -ca)

gmssl_run(p256keygen -pass ${_pass} -out server-key.pem)
gmssl_run(reqgen
  -C CN -ST Beijing -L Haidian -O GmSSL -OU ExternalIO
  -CN localhost
  -key server-key.pem
  -pass ${_pass}
  -out server-req.pem)
gmssl_run(reqsign
  -in server-req.pem
  -days 2
  -key_usage digitalSignature
  -ext_key_usage serverAuth
  -subject_dns_name localhost
  -cacert ca-cert.pem
  -key ca-key.pem
  -pass ${_pass}
  -out server-cert.pem)

foreach(_file IN ITEMS ca-cert.pem server-cert.pem server-key.pem)
  if(NOT EXISTS "${OUT_DIR}/${_file}")
    message(FATAL_ERROR "missing generated fixture: ${OUT_DIR}/${_file}")
  endif()
endforeach()
