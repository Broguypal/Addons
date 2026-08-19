cmake_minimum_required(VERSION 3.25)

project(TargetRing
    VERSION 3.0.0
    LANGUAGES CXX
)

add_library(_TargetRing SHARED
    TargetRingModule.cpp
    exports.def
)

# SceneHook.h must be byte-identical to the copy every other participant
# builds against.
target_include_directories(_TargetRing PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/../SceneHook")

set_target_properties(_TargetRing PROPERTIES
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../libs"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/../libs"
)

target_compile_features(_TargetRing PRIVATE cxx_std_17)

if(MSVC)
    target_compile_options(_TargetRing PRIVATE /W4 /EHsc)
else()
    target_compile_options(_TargetRing PRIVATE -Wall -Wextra -Wpedantic -m32)
    target_link_options(_TargetRing PRIVATE -m32 -static -static-libgcc -static-libstdc++)
endif()
