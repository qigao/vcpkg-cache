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

add_executable(gmssl-rsa-public-contract rsa-public-contract.c)
target_link_libraries(gmssl-rsa-public-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-public-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-public-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-public-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-signature-contract rsa-signature-contract.c)
target_link_libraries(gmssl-rsa-signature-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-signature-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-signature-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-signature-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-x509-rsa-contract x509-rsa-contract.c)
target_link_libraries(gmssl-x509-rsa-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-x509-rsa-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-x509-rsa-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-x509-rsa-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-rsa-private-contract rsa-private-contract.c)
target_link_libraries(gmssl-rsa-private-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-rsa-private-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-rsa-private-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-rsa-private-contract PRIVATE -fsanitize=address)
endif()

add_executable(gmssl-tls13-rsa-pss-contract tls13-rsa-pss-contract.c)
target_link_libraries(gmssl-tls13-rsa-pss-contract PRIVATE GmSSL::GmSSL)
set_target_properties(gmssl-tls13-rsa-pss-contract PROPERTIES
    C_STANDARD 11
    C_STANDARD_REQUIRED ON
    C_EXTENSIONS OFF)

if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang|AppleClang")
    target_compile_options(gmssl-tls13-rsa-pss-contract PRIVATE -fsanitize=address -fno-omit-frame-pointer)
    target_link_options(gmssl-tls13-rsa-pss-contract PRIVATE -fsanitize=address)
endif()
