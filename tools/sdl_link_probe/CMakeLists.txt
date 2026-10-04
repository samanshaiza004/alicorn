cmake_minimum_required(VERSION 3.16)
project(AlicornSDLLinkProbe NONE)

find_package(SDL3 CONFIG REQUIRED COMPONENTS SDL3-static)
if(NOT TARGET SDL3::SDL3-static)
    message(FATAL_ERROR "SDL3 static CMake target is unavailable")
endif()

# CMake owns the platform-specific transitive link requirements of SDL3.
# Generate the evaluated interface so Odin's final link can reuse those exact
# requirements without maintaining a second platform-specific list here.
file(GENERATE
    OUTPUT "${CMAKE_BINARY_DIR}/sdl3-static-link-interface.txt"
    CONTENT "$<JOIN:$<TARGET_PROPERTY:SDL3::SDL3-static,INTERFACE_LINK_LIBRARIES>,\n>"
)
