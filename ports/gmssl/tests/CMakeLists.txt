cmake_minimum_required(VERSION 3.16)
project(gmssl_tls12_alpn_contract C)

find_package(GmSSL CONFIG REQUIRED)

add_executable(gmssl-tls12-alpn-contract tls12-alpn-contract.c)
target_link_libraries(gmssl-tls12-alpn-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls12-alpn-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)
