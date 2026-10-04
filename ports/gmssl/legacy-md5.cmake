# Add the bounded legacy MD5 primitive required by protocol-compatibility
# consumers such as TURN and S3 SSE-C. This remains part of the private GmSSL
# provider package and intentionally does not recreate any OpenSSL compatibility
# surface.

file(COPY "${CMAKE_CURRENT_LIST_DIR}/md5.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/md5.c"
     DESTINATION "${SOURCE_PATH}/src")

vcpkg_replace_string(
    "${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c"
    "src/debug.c\nsrc/md5.c"
)
