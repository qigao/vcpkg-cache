cmake_minimum_required(VERSION 3.21)
project(QigaoLlvmMingwConsumer LANGUAGES C CXX)
add_executable(qigao_compiler_c smoke.c)
add_executable(qigao_compiler_cpp smoke.cpp)
