# Native RFC 3394 provider API, composed from GmSSL AES and secure memory APIs.
file(COPY "${CMAKE_CURRENT_LIST_DIR}/aes_key_wrap.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/aes_key_wrap.c"
     DESTINATION "${SOURCE_PATH}/src")
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c" "src/debug.c\nsrc/aes_key_wrap.c")
