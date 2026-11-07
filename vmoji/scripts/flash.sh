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

picotool is looked up in this order: \$PICOTOOL, PATH, then $PICOTOOL_INSTALLED
(built by setup-sdk.sh, or installed by the Pico VS Code extension). The first one with USB
support is used; the copy the SDK builds during a firmware build has none and cannot flash.
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
        "$PICOTOOL_INSTALLED"; do
        if picotool_has_usb "$candidate"; then
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
    cat >&2 <<EOF
No picotool with USB support found. Build one with vmoji/scripts/setup-sdk.sh,
or copy $UF2_SHOWN onto the RPI-RP2 drive (hold BOOTSEL while plugging in).
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
