cmake_minimum_required(VERSION 3.22)
project(ugrep LANGUAGES C CXX)

# Native MSVC adapter for the same sources as upstream src/Makefile.am and
# lib/Makefile.am. Avoid the upstream .sln's sibling library checkouts.
if(NOT WIN32 OR NOT MSVC)
    message(FATAL_ERROR "This adapter requires native Windows MSVC; POSIX uses upstream configure.")
endif()
find_package(pcre2 CONFIG REQUIRED)

add_library(reflex STATIC
    "${UGREP_SOURCE_DIR}/lib/convert.cpp"
    "${UGREP_SOURCE_DIR}/lib/debug.cpp"
    "${UGREP_SOURCE_DIR}/lib/error.cpp"
    "${UGREP_SOURCE_DIR}/lib/input.cpp"
    "${UGREP_SOURCE_DIR}/lib/matcher.cpp"
    "${UGREP_SOURCE_DIR}/lib/pattern.cpp"
    "${UGREP_SOURCE_DIR}/lib/posix.cpp"
    "${UGREP_SOURCE_DIR}/lib/simd.cpp"
    "${UGREP_SOURCE_DIR}/lib/unicode.cpp"
    "${UGREP_SOURCE_DIR}/lib/utf8.cpp"
    "${UGREP_SOURCE_DIR}/lib/block_scripts.cpp"
    "${UGREP_SOURCE_DIR}/lib/language_scripts.cpp"
    "${UGREP_SOURCE_DIR}/lib/letter_scripts.cpp"
    "${UGREP_SOURCE_DIR}/lib/letter_case.cpp"
    "${UGREP_SOURCE_DIR}/lib/composer.cpp"
)
target_include_directories(reflex PUBLIC "${UGREP_SOURCE_DIR}/include")
target_compile_features(reflex PUBLIC cxx_std_11)
target_compile_definitions(reflex PUBLIC _CRT_SECURE_NO_WARNINGS _CRT_NONSTDC_NO_WARNINGS WITH_NO_INDENT PRIVATE WITH_NO_CODEGEN)

add_executable(ugrep
    "${UGREP_SOURCE_DIR}/src/ugrep.cpp"
    "${UGREP_SOURCE_DIR}/src/cnf.cpp"
    "${UGREP_SOURCE_DIR}/src/glob.cpp"
    "${UGREP_SOURCE_DIR}/src/output.cpp"
    "${UGREP_SOURCE_DIR}/src/query.cpp"
    "${UGREP_SOURCE_DIR}/src/screen.cpp"
    "${UGREP_SOURCE_DIR}/src/stats.cpp"
    "${UGREP_SOURCE_DIR}/src/vkey.cpp"
    "${UGREP_SOURCE_DIR}/src/zopen.c"
)
target_compile_definitions(ugrep PRIVATE HAVE_PCRE2 WITH_COLOR)
target_link_libraries(ugrep PRIVATE reflex PCRE2::8BIT ws2_32)

add_executable(ugrep-indexer
    "${UGREP_SOURCE_DIR}/src/ugrep-indexer.cpp"
    "${UGREP_SOURCE_DIR}/src/glob.cpp"
    "${UGREP_SOURCE_DIR}/src/zopen.c"
)
target_link_libraries(ugrep-indexer PRIVATE reflex ws2_32)
install(TARGETS ugrep ugrep-indexer RUNTIME DESTINATION bin)
install(FILES "${UGREP_SOURCE_DIR}/man/ugrep.1" "${UGREP_SOURCE_DIR}/man/ugrep-indexer.1" DESTINATION share/ugrep)
