# Normalize public Windows preprocessor guards for ordinary MSVC consumers.
# MSVC guarantees _WIN32; WIN32 is not a language/toolchain guarantee.

foreach(_gmssl_public_header IN ITEMS
        "${SOURCE_PATH}/include/gmssl/socket.h"
        "${SOURCE_PATH}/include/gmssl/dylib.h")
    vcpkg_replace_string(
        "${_gmssl_public_header}"
        "#ifdef WIN32"
        "#if defined(_WIN32) || defined(WIN32)"
    )
endforeach()

unset(_gmssl_public_header)
