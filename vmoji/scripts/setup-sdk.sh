#!/usr/bin/env bash
# Download the Raspberry Pi Pico SDK and build picotool (with USB support, so it can flash),
# at the versions vmoji/CMakeLists.txt pins.
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

1. Clones pico-sdk $SDK_VERSION (sdkVersion in vmoji/CMakeLists.txt), with its submodules,
   into $SDK_DIR
   Override with PICO_SDK_PATH.
2. Builds picotool $PICOTOOL_VERSION (picotoolVersion) with USB support, which flash.sh needs,
   into $PICOTOOL_PREFIX

Each step is skipped when already done. The paths match the Pico VS Code extension's, so the
two share one copy.
EOF
        exit 0
        ;;
    "") ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

setup_sdk() {
    if [ -f "$SDK_DIR/pico_sdk_init.cmake" ]; then
        echo "Pico SDK already present: $SDK_DIR"
        return 0
    fi
    if [ -e "$SDK_DIR" ] && [ -n "$(ls -A "$SDK_DIR" 2>/dev/null)" ]; then
        echo "$SDK_DIR exists but is not a Pico SDK. Remove it or set PICO_SDK_PATH." >&2
        return 1
    fi

    command -v git >/dev/null || { echo "git is required (sudo apt install git)" >&2; return 1; }
    mkdir -p "$(dirname "$SDK_DIR")" || return 1
    echo "Cloning pico-sdk $SDK_VERSION into $SDK_DIR ..."
    # Into a temporary name, so an interrupted clone can't pass as a complete SDK later: the check
    # above only looks at one file, which exists long before the submodules arrive.
    local partial="$SDK_DIR.partial"
    rm -rf "$partial"
    # Shallow: only this release and its submodules (TinyUSB for USB serial, among others).
    if ! git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$SDK_VERSION" --recurse-submodules \
        --shallow-submodules https://github.com/raspberrypi/pico-sdk.git "$partial"; then
        rm -rf "$partial"
        echo "Clone failed." >&2
        return 1
    fi
    rmdir "$SDK_DIR" 2>/dev/null # An empty folder is allowed above; mv needs it gone.
    mv "$partial" "$SDK_DIR" || return 1
}

# The SDK can build picotool by itself, but never with USB support (see common.sh), so flashing
# needs this separate build. Installed where the SDK's find_package and the extension look.
setup_picotool() {
    if picotool_has_usb "$PICOTOOL_INSTALLED"; then
        echo "picotool already present: $PICOTOOL_INSTALLED"
        return 0
    fi
    if ! pkg-config --exists libusb-1.0 2>/dev/null; then
        echo "picotool needs the libusb headers: sudo apt install libusb-1.0-0-dev pkg-config" >&2
        return 1
    fi
    local tool missing=""
    for tool in cmake ninja g++; do
        command -v "$tool" >/dev/null || missing="$missing $tool"
    done
    if [ -n "$missing" ]; then
        echo "Missing:$missing. See scripts/doctor.sh firmware." >&2
        return 1
    fi

    local work
    work="$(mktemp -d)" || return 1
    echo "Building picotool $PICOTOOL_VERSION into $PICOTOOL_PREFIX ..."
    if git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$PICOTOOL_VERSION" \
        https://github.com/raspberrypi/picotool.git "$work/src" \
        && cmake -S "$work/src" -B "$work/build" -G Ninja -DCMAKE_BUILD_TYPE=Release \
            -DPICO_SDK_PATH="$SDK_DIR" -DPICOTOOL_FLAT_INSTALL=1 \
            -DCMAKE_INSTALL_PREFIX="$PICOTOOL_PREFIX" >"$work/log" 2>&1 \
        && cmake --build "$work/build" >>"$work/log" 2>&1 \
        && cmake --install "$work/build" >>"$work/log" 2>&1 \
        && picotool_has_usb "$PICOTOOL_INSTALLED"; then
        rm -rf "$work"
        return 0
    fi
    [ -f "$work/log" ] && tail -20 "$work/log" >&2
    rm -rf "$work"
    echo "picotool build failed." >&2
    return 1
}

setup_sdk || exit 1
setup_picotool || exit 1
echo "Done. Build the firmware with vmoji/scripts/build.sh"
