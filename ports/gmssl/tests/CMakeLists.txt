cmake_minimum_required(VERSION 3.16)
project(gmssl_tls12_alpn_contract C)

find_package(GmSSL CONFIG REQUIRED)

add_executable(gmssl-tls12-alpn-contract tls12-alpn-contract.c)
target_link_libraries(gmssl-tls12-alpn-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls12-alpn-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls12-alpn-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls12-alpn-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls-version-range-contract tls-version-range-contract.c)
target_link_libraries(gmssl-tls-version-range-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-version-range-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls-version-range-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls-version-range-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls-version-range-dispatch-contract tls-version-range-dispatch-contract.c)
target_link_libraries(gmssl-tls-version-range-dispatch-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls-version-range-dispatch-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls-version-range-dispatch-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls-version-range-dispatch-contract PRIVATE -fsanitize=address)
endif()
