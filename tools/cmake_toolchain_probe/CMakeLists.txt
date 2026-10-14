cmake_minimum_required(VERSION 3.16)
project(AlicornNativeLinkToolchainProbe LANGUAGES C CXX)

if(NOT MSVC)
    message(FATAL_ERROR "Alicorn static native link recipes currently require the MSVC ABI and toolchain.")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "Alicorn static native link recipes currently require a 64-bit compiler target.")
endif()
