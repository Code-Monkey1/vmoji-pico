#!/usr/bin/env bash
# Flash vmoji/build/vmoji.uf2 over USB with picotool.
#
# Usage: vmoji/scripts/flash.sh [-h|--help]
# Env:   PICOTOOL=/path/to/picotool
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
. scripts/common.sh

case "${1:-}" in
    -h | --help)
        cat <<EOF
Usage: vmoji/scripts/flash.sh [-h|--help]

Loads $UF2_SHOWN onto a Pico connected over USB, then runs it.
A board running vmoji is rebooted into BOOTSEL by picotool (-f), so no button press
is needed. A blank or crashed board: hold BOOTSEL while plugging it in.

picotool is looked up in this order: \$PICOTOOL, PATH, the Pico VS Code extension
(~/.pico-sdk/picotool/$PICOTOOL_VERSION), then the copy the SDK builds into $BUILD_SHOWN.
EOF
        exit 0
        ;;
    "") ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

find_picotool() {
    local candidate
    for candidate in \
        "${PICOTOOL:-}" \
        "$(command -v picotool 2>/dev/null)" \
        "$HOME/.pico-sdk/picotool/$PICOTOOL_VERSION/picotool/picotool" \
        "$BUILD_DIR/_deps/picotool/picotool"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            echo "$candidate"
            return 0
        fi
    done
    return 1
}

if [ ! -f "$UF2" ]; then
    echo "No $UF2_SHOWN yet. Build it first: vmoji/scripts/build.sh" >&2
    exit 1
fi
if ! picotool="$(find_picotool)"; then
    echo "picotool not found. Build once with vmoji/scripts/build.sh (the SDK builds it)," >&2
    echo "or copy $UF2_SHOWN onto the RPI-RP2 drive (hold BOOTSEL while plugging in)." >&2
    exit 1
fi

# Built without libusb headers, picotool cannot talk to USB at all ("Unknown command: load").
if ! "$picotool" help load >/dev/null 2>&1; then
    cat >&2 <<EOF
$picotool was built without USB support, so it cannot flash.
Install the USB headers and rebuild (the SDK rebuilds picotool):
  sudo apt install libusb-1.0-0-dev pkg-config
  vmoji/scripts/build.sh --clean
Or copy $UF2_SHOWN onto the RPI-RP2 drive (hold BOOTSEL while plugging in).
EOF
    exit 1
fi

# -f: reboot a running board into BOOTSEL first. -x: run the new firmware after loading.
if ! "$picotool" load -fx "$UF2"; then
    cat >&2 <<EOF

Flashing failed. Common causes:
  - No board found: check the USB cable (a data cable, not charge-only).
  - Permission denied: install the udev rule (docs/getting-started.md).
  - Board not responding: hold BOOTSEL while plugging it in, then re-run,
    or copy $UF2_SHOWN onto the RPI-RP2 drive that appears.
EOF
    exit 1
fi
