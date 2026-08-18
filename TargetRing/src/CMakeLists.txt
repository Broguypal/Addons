cmake_minimum_required(VERSION 3.25)

project(TargetRing
    VERSION 2.3.0
    LANGUAGES CXX
)

add_library(_TargetRing SHARED
    TargetRingModule.cpp
    exports.def
)

set_target_properties(_TargetRing PROPERTIES PREFIX "")

target_compile_features(_TargetRing PRIVATE cxx_std_17)

if(MSVC)
    target_compile_options(_TargetRing PRIVATE /W4 /EHsc)
else()
    target_compile_options(_TargetRing PRIVATE -Wall -Wextra -Wpedantic -m32)
    target_link_options(_TargetRing PRIVATE -m32 -static -static-libgcc -static-libstdc++)
endif()
