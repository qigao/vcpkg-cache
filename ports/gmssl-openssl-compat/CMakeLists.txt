cmake_minimum_required(VERSION 3.16)
project(gmssl_openssl_compat C)

find_package(GmSSL CONFIG REQUIRED)

set(crypto_src
    src/err.c
    src/bio.c
    src/evp.c
    src/rand.c
    src/asn1.c
    src/x509.c
    src/x509_vfy.c
    src/crypto.c
    src/pem.c
    src/dh.c
)

add_library(crypto ${crypto_src})
target_include_directories(crypto
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)
target_link_libraries(crypto PUBLIC GmSSL::GmSSL)

add_library(ssl src/ssl.c)
target_include_directories(ssl
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
)
target_link_libraries(ssl PUBLIC crypto)

set_target_properties(crypto ssl PROPERTIES DEBUG_POSTFIX d)
if(WIN32)
    set_target_properties(crypto ssl PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS ON)
endif()

install(TARGETS crypto ssl
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
    RUNTIME DESTINATION bin
)
install(DIRECTORY include/openssl DESTINATION include)
