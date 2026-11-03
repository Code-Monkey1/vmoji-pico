#!/usr/bin/env bash
# Build the firmware into vmoji/build/vmoji.uf2.
#
# Usage: vmoji/scripts/build.sh [-h|--help] [--clean]
# Env:   PICO_SDK_PATH=/path/to/pico-sdk   (default: ~/.pico-sdk/sdk/<version>)
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
. scripts/common.sh

clean=0
for arg in "$@"; do
    case "$arg" in
        -h | --help)
            cat <<EOF
Usage: vmoji/scripts/build.sh [-h|--help] [--clean]

Configures (first time) and builds the firmware with CMake + Ninja.
Output: $UF2_SHOWN
  --clean   delete $BUILD_SHOWN first

SDK: $SDK_DIR (get it with setup-sdk.sh). Override with PICO_SDK_PATH, except when
the Pico VS Code extension is installed: its SDK and toolchain always win.
Toolchain: arm-none-eabi-gcc from PATH, or the Pico VS Code extension's if installed.
EOF
            exit 0
            ;;
        --clean) clean=1 ;;
        *) echo "Unknown argument: $arg (see --help)" >&2; exit 2 ;;
    esac
done

if [ ! -f "$SDK_DIR/pico_sdk_init.cmake" ]; then
    echo "No Pico SDK at $SDK_DIR. Run vmoji/scripts/setup-sdk.sh (or set PICO_SDK_PATH)." >&2
    exit 1
fi
[ $clean -eq 1 ] && rm -rf "$BUILD_DIR"

# Configure once; later builds reuse the cache (also when VS Code created it).
if [ ! -f "$BUILD_DIR/CMakeCache.txt" ]; then
    cmake -S . -B "$BUILD_DIR" -G Ninja -DPICO_SDK_PATH="$SDK_DIR" || exit 1
fi
cmake --build "$BUILD_DIR" || exit 1
echo "Built $UF2_SHOWN. Flash it with vmoji/scripts/flash.sh"
