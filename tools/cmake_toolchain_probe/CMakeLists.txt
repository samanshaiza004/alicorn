cmake_minimum_required(VERSION 3.16)
cmake_policy(SET CMP0091 NEW)
project(AlicornNativeLinkToolchainProbe LANGUAGES C CXX)

if(NOT MSVC)
    message(FATAL_ERROR "Alicorn static native link recipes currently require the MSVC ABI and toolchain.")
endif()

if(NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
    message(FATAL_ERROR "Alicorn static native link recipes currently require a 64-bit compiler target.")
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Windows")
    message(FATAL_ERROR "Alicorn static native link recipes currently require a Windows target.")
endif()

if(NOT CMAKE_MSVC_RUNTIME_LIBRARY STREQUAL "MultiThreaded")
    message(FATAL_ERROR "Alicorn static native link recipes currently require the static MSVC CRT (/MT).")
endif()

function(alicorn_json_escape output value)
    string(REPLACE "\\" "\\\\" escaped "${value}")
    string(REPLACE "\"" "\\\"" escaped "${escaped}")
    string(REPLACE "\n" "\\n" escaped "${escaped}")
    string(REPLACE "\r" "\\r" escaped "${escaped}")
    set(${output} "${escaped}" PARENT_SCOPE)
endfunction()

alicorn_json_escape(c_compiler "${CMAKE_C_COMPILER}")
alicorn_json_escape(cxx_compiler "${CMAKE_CXX_COMPILER}")
alicorn_json_escape(windows_sdk_version "${CMAKE_VS_WINDOWS_TARGET_PLATFORM_VERSION}")

# CMAKE_SIZEOF_VOID_P is a configure-time variable, not a portable cache
# contract. Record the evaluated toolchain facts while they are in scope so
# the caller validates the compiler CMake actually configured.
file(WRITE "${CMAKE_BINARY_DIR}/alicorn-toolchain-report.json"
    "{\n"
    "  \"schemaVersion\": 1,\n"
    "  \"pointerSize\": ${CMAKE_SIZEOF_VOID_P},\n"
    "  \"cCompiler\": \"${c_compiler}\",\n"
    "  \"cCompilerId\": \"${CMAKE_C_COMPILER_ID}\",\n"
    "  \"cCompilerVersion\": \"${CMAKE_C_COMPILER_VERSION}\",\n"
    "  \"cxxCompiler\": \"${cxx_compiler}\",\n"
    "  \"cxxCompilerId\": \"${CMAKE_CXX_COMPILER_ID}\",\n"
    "  \"cxxCompilerVersion\": \"${CMAKE_CXX_COMPILER_VERSION}\",\n"
    "  \"targetSystem\": \"${CMAKE_SYSTEM_NAME}\",\n"
    "  \"targetProcessor\": \"${CMAKE_SYSTEM_PROCESSOR}\",\n"
    "  \"generator\": \"${CMAKE_GENERATOR}\",\n"
    "  \"generatorPlatform\": \"${CMAKE_GENERATOR_PLATFORM}\",\n"
    "  \"visualStudioPlatform\": \"${CMAKE_VS_PLATFORM_NAME}\",\n"
    "  \"windowsSdkVersion\": \"${windows_sdk_version}\",\n"
    "  \"crt\": \"${CMAKE_MSVC_RUNTIME_LIBRARY}\"\n"
    "}\n"
)
