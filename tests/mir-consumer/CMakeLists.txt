cmake_minimum_required(VERSION 3.20)
project(MIRConsumer LANGUAGES C)

find_package(MIR CONFIG REQUIRED)

add_executable(mir_consumer main.c)
target_compile_features(mir_consumer PRIVATE c_std_11)
target_link_libraries(mir_consumer PRIVATE MIR::MIR)
