#!/usr/bin/env bash
# Flash vmoji-fw/build/vmoji.uf2 over USB with picotool.
#
# Usage: vmoji-fw/scripts/flash.sh [-h|--help]
# Env:   PICOTOOL=/path/to/picotool
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1
. scripts/common.sh

case "${1:-}" in
    -h | --help)
        cat <<EOF
Usage: vmoji-fw/scripts/flash.sh [-h|--help]

Loads $UF2_SHOWN onto a Pico connected over USB, then runs it.
A board running vmoji is rebooted into BOOTSEL by picotool, so no button press is needed.
A blank or crashed board: hold BOOTSEL while plugging it in.

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
    echo "No $UF2_SHOWN yet. Build it first: vmoji-fw/scripts/build.sh" >&2
    exit 1
fi
if ! picotool="$(find_picotool)"; then
    cat >&2 <<EOF
No picotool with USB support found. Build one with vmoji-fw/scripts/setup-sdk.sh,
or copy $UF2_SHOWN onto the RPI-RP2 drive (hold BOOTSEL while plugging in).
EOF
    exit 1
fi

flash_failed() {
    cat >&2 <<EOF

Flashing failed. Common causes:
  - No board found: check the USB cable (a data cable, not charge-only).
  - Permission denied: install the udev rule (docs/getting-started.md).
  - Board not responding: hold BOOTSEL while plugging it in, then re-run,
    or copy $UF2_SHOWN onto the RPI-RP2 drive that appears.
EOF
    exit 1
}

# Is a Pico in BOOTSEL? From sysfs, because `picotool info` can't say: v2.3.0 segfaults on an RP2040
# in BOOTSEL.
in_bootsel() {
    local dev
    for dev in /sys/bus/usb/devices/*/; do
        [ "$(cat "$dev/idVendor" 2>/dev/null)" = "2e8a" ] \
            && [ "$(cat "$dev/idProduct" 2>/dev/null)" = "0003" ] && return 0
    done
    return 1
}

# Separate picotool runs, not `load -f`: that waits for the board in one process, and in a container
# that process never sees it come back. A new process finds it.
if ! in_bootsel; then
    "$picotool" reboot -f -u || flash_failed
    for _ in $(seq 20); do
        in_bootsel && break
        sleep 0.5
    done
fi
# -x: run the new firmware after loading. If the wait above ran out, this reports no board. A few
# tries, because the board can show up in sysfs just before udev gives us permission to open it.
for _ in 1 2 3; do
    "$picotool" load -x "$UF2" && exit 0
    sleep 1
done
flash_failed
