# Add the bounded legacy DES-CBC primitive required by protocol-compatibility
# consumers such as SNMPv3 USM. This remains part of the private GmSSL provider
# package and intentionally does not recreate any OpenSSL compatibility surface.

file(COPY "${CMAKE_CURRENT_LIST_DIR}/des.h"
     DESTINATION "${SOURCE_PATH}/include/gmssl")
file(COPY "${CMAKE_CURRENT_LIST_DIR}/des.c"
     DESTINATION "${SOURCE_PATH}/src")

vcpkg_replace_string(
    "${SOURCE_PATH}/CMakeLists.txt"
    "src/debug.c"
    "src/debug.c\nsrc/des.c"
)
