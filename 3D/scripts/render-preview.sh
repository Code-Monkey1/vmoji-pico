#!/usr/bin/env bash
# Render the assembly preview to a PNG, by default a gitignored one. --update-docs refreshes the
# tracked README image instead.
#
# Fixed camera and size, so re-running it after a design change gives a comparable image.
# OpenSCAD's PNG export needs OpenGL, so with no display this wraps itself in xvfb-run.
#
# Usage: 3D/scripts/render-preview.sh [-h|--help] [--update-docs] [output.png]
# Env:   OPENSCAD=/path/to/openscad
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

OPENSCAD="${OPENSCAD:-openscad}"
OUT="preview.png"
DOCS_IMAGE="../docs/images/assembly-preview.png"
# Eye (x,y,z) then look-at center (x,y,z), in model mm: front-left, above the stack.
CAMERA="-209,-377,250,30,0,30"
SIZE="1600,1000"

for arg in "$@"; do
    case "$arg" in
        -h | --help)
            cat <<EOF
Usage: 3D/scripts/render-preview.sh [-h|--help] [--update-docs] [output.png]

Render assembly-preview.scad (all parts shown, default parameters) to a PNG.
Default output: 3D/preview.png (gitignored). Relative paths are from 3D/.
  --update-docs   write docs/images/assembly-preview.png, the tracked README image

Needs OpenGL. With no display it runs under xvfb-run (sudo apt install xvfb).
EOF
            exit 0
            ;;
        --update-docs) OUT="$DOCS_IMAGE" ;;
        -*) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
        *) OUT="$arg" ;;
    esac
done

RUN=()
if [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
    if ! command -v xvfb-run >/dev/null; then
        echo "No display, and OpenSCAD needs OpenGL to write a PNG. Install a virtual display:" >&2
        echo "  sudo apt install xvfb" >&2
        exit 1
    fi
    RUN=(xvfb-run -a -s "-screen 0 ${SIZE%,*}x${SIZE#*,}x24")
fi

mkdir -p "$(dirname "$OUT")" || exit 1
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
if ! "${RUN[@]}" "$OPENSCAD" -o "$OUT" --imgsize="$SIZE" --camera="$CAMERA" --colorscheme=Tomorrow \
    assembly-preview.scad >"$LOG" 2>&1 || grep -qE "ERROR|Assertion" "$LOG"; then
    grep -E "ERROR|WARNING|Assertion" "$LOG" || tail -5 "$LOG"
    echo "FAILED to render $OUT" >&2
    exit 1
fi
echo "Wrote $(readlink -f "$OUT")"
