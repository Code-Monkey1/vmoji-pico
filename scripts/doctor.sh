#!/usr/bin/env bash
# Check that this machine has everything needed to work on vmoji, and say how to fix what is
# missing. Read-only: it installs nothing.
#
# Usage: scripts/doctor.sh [-h|--help] [firmware|dashboard|3d ...]   (default: all)
set -u
ROOT="$(dirname "$(readlink -f "$0")")/.."
cd "$ROOT" || exit 1

usage() {
    cat <<EOF
Usage: scripts/doctor.sh [-h|--help] [firmware|dashboard|3d ...]

Checks the tools each part of the repo needs (default: all parts) and prints the
command that installs anything missing. Exits 1 if a required item is missing.
Setup guide: docs/getting-started.md
EOF
}

AREAS=()
for arg in "$@"; do
    case "$arg" in
        -h | --help) usage; exit 0 ;;
        firmware | dashboard | 3d) AREAS+=("$arg") ;;
        *) echo "Unknown argument: $arg (see --help)" >&2; exit 2 ;;
    esac
done
[ ${#AREAS[@]} -eq 0 ] && AREAS=(firmware dashboard 3d)

missing=0
warned=0
ok() { printf '  ok      %s\n' "$1"; }
bad() { printf '  MISSING %s\n          fix: %s\n' "$1" "$2"; missing=1; }
warn() { printf '  warn    %s\n          fix: %s\n' "$1" "$2"; warned=1; }

# version_ge 3.16.0 3.13 -> true
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; }

need_cmd() { # need_cmd <command> <apt package> [label]
    if command -v "$1" >/dev/null 2>&1; then ok "${3:-$1}"; else bad "${3:-$1}" "sudo apt install $2"; fi
}

check_firmware() {
    echo "Firmware (vmoji/)"
    need_cmd git git
    if command -v cmake >/dev/null 2>&1; then
        local v
        v="$(cmake --version | sed -n 's/^cmake version //p')"
        if version_ge "$v" 3.16; then ok "cmake $v"; else bad "cmake $v (need >= 3.16)" "sudo apt install cmake"; fi
    else
        bad "cmake" "sudo apt install cmake"
    fi
    need_cmd ninja ninja-build
    need_cmd python3 python3 "python3 (the SDK's build scripts use it)"
    need_cmd gcc build-essential "host C compiler (gcc)"
    need_cmd g++ build-essential "host C++ compiler (g++)"
    # With the Pico VS Code extension installed, CMakeLists.txt includes its hook, which
    # forces the extension's SDK and toolchain (see vmoji/scripts/common.sh).
    local hook="$HOME/.pico-sdk/cmake/pico-vscode.cmake" toolchain_version
    toolchain_version="$(sed -n 's/^set(toolchainVersion \(.*\))$/\1/p' vmoji/CMakeLists.txt)"
    if [ -f "$hook" ] && [ -x "$HOME/.pico-sdk/toolchain/$toolchain_version/bin/arm-none-eabi-gcc" ]; then
        ok "ARM cross compiler (VS Code extension, $toolchain_version)"
    else
        need_cmd arm-none-eabi-gcc "gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib" "ARM cross compiler"
    fi
    local sdk_version sdk_dir picotool_version picotool=""
    sdk_version="$(sed -n 's/^set(sdkVersion \(.*\))$/\1/p' vmoji/CMakeLists.txt)"
    picotool_version="$(sed -n 's/^set(picotoolVersion \(.*\))$/\1/p' vmoji/CMakeLists.txt)"
    # Flashing needs a picotool built with USB support. The copy the SDK builds during a firmware
    # build never has it, so libusb headers alone are not enough (see vmoji/scripts/common.sh).
    for candidate in "$(command -v picotool 2>/dev/null)" \
        "$HOME/.pico-sdk/picotool/$picotool_version/picotool/picotool"; do
        if [ -n "$candidate" ] && [ -x "$candidate" ] && "$candidate" help load >/dev/null 2>&1; then
            picotool="$candidate"
            break
        fi
    done
    if [ -n "$picotool" ]; then
        ok "picotool with USB support ($picotool)"
    else
        bad "picotool with USB support (needed to flash)" "vmoji/scripts/setup-sdk.sh"
    fi
    sdk_dir="${PICO_SDK_PATH:-$HOME/.pico-sdk/sdk/$sdk_version}"
    [ -f "$hook" ] && sdk_dir="$HOME/.pico-sdk/sdk/$sdk_version"
    if [ -f "$sdk_dir/pico_sdk_init.cmake" ]; then
        ok "Pico SDK $sdk_version ($sdk_dir)"
    else
        bad "Pico SDK $sdk_version (looked in $sdk_dir)" "vmoji/scripts/setup-sdk.sh"
    fi
    if [ -n "${VMOJI_DEVCONTAINER:-}" ]; then
        # The host's udev sets the board's permissions, so a rule in here could never count.
        printf '  note    udev rule for the Pico: goes on the host, not checked here (see docs/getting-started.md)\n'
    elif grep -qs '2e8a' /etc/udev/rules.d/*.rules /lib/udev/rules.d/*.rules; then
        ok "udev rule for the Pico (flash without sudo)"
    else
        warn "no udev rule for the Pico (picotool will need sudo)" "see docs/getting-started.md"
    fi
}

check_dashboard() {
    echo "Dashboard (tools/dashboard/)"
    if command -v python3 >/dev/null 2>&1; then
        local v
        v="$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')"
        if version_ge "$v" 3.10; then ok "python3 $v"; else bad "python3 $v (need >= 3.10)" "install Python 3.10+"; fi
    else
        bad "python3" "sudo apt install python3"
    fi
    if python3 -c 'import ensurepip, venv' >/dev/null 2>&1; then
        ok "python3 venv"
    else
        bad "python3 venv" "sudo apt install python3-venv"
    fi
    if [ -x tools/dashboard/.venv/bin/python ]; then
        ok "dashboard venv (tools/dashboard/.venv)"
    else
        bad "dashboard venv" "cd tools/dashboard && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
    fi
    # ldconfig lives in /sbin, which is not on a normal user's PATH on Debian.
    if { ldconfig -p 2>/dev/null || /sbin/ldconfig -p 2>/dev/null; } | grep -q 'libxcb-cursor.so.0'; then
        ok "libxcb-cursor0 (Qt needs it to open windows)"
    else
        # Only windows need it: with no display, the tests and command-line tools still work.
        if [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
            bad "libxcb-cursor0 (Qt needs it to open windows)" "sudo apt install libxcb-cursor0"
        else
            warn "libxcb-cursor0 (Qt needs it to open windows)" "sudo apt install libxcb-cursor0"
        fi
    fi
    if id -nG | tr ' ' '\n' | grep -qx dialout; then
        ok "serial port access (dialout group)"
    else
        warn "not in the dialout group (no access to /dev/ttyACM*)" \
            "sudo usermod -aG dialout \$USER, then log out and back in"
    fi
}

check_3d() {
    echo "3D (3D/)"
    need_cmd openscad openscad
    local libdirs found=""
    # OpenSCAD's user and system library folders, plus anything on OPENSCADPATH.
    libdirs="$HOME/.local/share/OpenSCAD/libraries:/usr/share/openscad/libraries"
    libdirs="$libdirs:/usr/local/share/openscad/libraries${OPENSCADPATH:+:$OPENSCADPATH}"
    local IFS=:
    for d in $libdirs; do
        [ -f "$d/BOSL2/std.scad" ] && found="$d/BOSL2"
    done
    unset IFS
    if [ -n "$found" ]; then
        ok "BOSL2 library ($found)"
    else
        bad "BOSL2 library" "git clone https://github.com/BelfrySCAD/BOSL2.git ~/.local/share/OpenSCAD/libraries/BOSL2"
    fi
    need_cmd python3 python3 "python3 (used by the collision check)"
}

for area in "${AREAS[@]}"; do
    case "$area" in
        firmware) check_firmware ;;
        dashboard) check_dashboard ;;
        3d) check_3d ;;
    esac
    echo
done

if [ $missing -ne 0 ]; then
    echo "Some required items are missing (see fix: lines). Guide: docs/getting-started.md"
    exit 1
fi
[ $warned -ne 0 ] && echo "All required items found (see warnings above)." || echo "All good."
