# RFC 8017 encodings over the provider's RSA and digest primitives.
file(COPY "${CMAKE_CURRENT_LIST_DIR}/rsa_ext.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/rsa_ext.c"
     DESTINATION "${SOURCE_PATH}/src")
vcpkg_replace_string("${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c" "src/debug.c\nsrc/rsa_ext.c")
