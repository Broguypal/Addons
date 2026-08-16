cmake_minimum_required(VERSION 3.25)

project(TargetRing
    VERSION 1.1.0
    LANGUAGES CXX RC
)

add_library(TargetRing SHARED
    TargetRing.cpp
    TargetRing.rc
    PluginInterface.h
    exports.def
)

set_target_properties(TargetRing PROPERTIES PREFIX "")

target_compile_features(TargetRing PRIVATE cxx_std_17)

if(MSVC)
    target_compile_options(TargetRing PRIVATE /W4 /EHsc)
else()
    target_compile_options(TargetRing PRIVATE -Wall -Wextra -Wpedantic -m32)
    target_link_options(TargetRing PRIVATE -m32 -static -static-libgcc -static-libstdc++)
endif()
