#!/bin/sh
# Build _Vanish.dll with mingw-w64. Must be the i686 (32-bit) toolchain.
#   Debian/Ubuntu:  apt install g++-mingw-w64-i686
set -e
mkdir -p ../libs
i686-w64-mingw32-g++ -std=c++17 -O2 -s -shared -static \
    -static-libgcc -static-libstdc++ \
    -Wall -Wextra -Wno-unused-parameter \
    -o ../libs/_Vanish.dll VanishModule.cpp -lkernel32
echo "Built ../libs/_Vanish.dll"
