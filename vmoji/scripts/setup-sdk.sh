#!/usr/bin/env bash
# Download the Raspberry Pi Pico SDK at the version vmoji/CMakeLists.txt pins.
#
# Usage: vmoji/scripts/setup-sdk.sh [-h|--help]
# Env:   PICO_SDK_PATH=/where/to/put/it   (default: ~/.pico-sdk/sdk/<version>)
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
. scripts/common.sh

case "${1:-}" in
    -h | --help)
        cat <<EOF
Usage: vmoji/scripts/setup-sdk.sh [-h|--help]

Clones pico-sdk $SDK_VERSION (the sdkVersion in vmoji/CMakeLists.txt), with its
submodules, into:
  $SDK_DIR
Override with PICO_SDK_PATH. Does nothing if that folder already holds the SDK.
The path matches the Pico VS Code extension's, so the two share one checkout.
EOF
        exit 0
        ;;
    "") ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

if [ -f "$SDK_DIR/pico_sdk_init.cmake" ]; then
    echo "Pico SDK already present: $SDK_DIR"
    exit 0
fi
if [ -e "$SDK_DIR" ] && [ -n "$(ls -A "$SDK_DIR" 2>/dev/null)" ]; then
    echo "$SDK_DIR exists but is not a Pico SDK. Remove it or set PICO_SDK_PATH." >&2
    exit 1
fi

command -v git >/dev/null || { echo "git is required (sudo apt install git)" >&2; exit 1; }
mkdir -p "$(dirname "$SDK_DIR")" || exit 1
echo "Cloning pico-sdk $SDK_VERSION into $SDK_DIR ..."
# Shallow: only this release and its submodules (TinyUSB for USB serial, among others).
if ! git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$SDK_VERSION" --recurse-submodules \
    --shallow-submodules https://github.com/raspberrypi/pico-sdk.git "$SDK_DIR"; then
    rm -rf "$SDK_DIR"
    echo "Clone failed." >&2
    exit 1
fi
echo "Done. Build the firmware with vmoji/scripts/build.sh"
