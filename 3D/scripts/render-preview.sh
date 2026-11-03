#!/usr/bin/env bash
# Render the assembly preview to docs/images/assembly-preview.png (the README image).
#
# Fixed camera and size, so re-running it after a design change gives a comparable image.
# OpenSCAD's PNG export needs OpenGL: run it from a desktop session (or under xvfb-run).
#
# Usage: 3D/scripts/render-preview.sh [-h|--help] [output.png]
# Env:   OPENSCAD=/path/to/openscad
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

OPENSCAD="${OPENSCAD:-openscad}"
OUT="${1:-../docs/images/assembly-preview.png}"
# Eye (x,y,z) then look-at center (x,y,z), in model mm: front-left, above the stack.
CAMERA="-209,-377,250,30,0,30"
SIZE="1600,1000"

case "${1:-}" in
    -h | --help)
        cat <<EOF
Usage: 3D/scripts/render-preview.sh [-h|--help] [output.png]

Render assembly-preview.scad (all parts shown, default parameters) to a PNG.
Default output: docs/images/assembly-preview.png (relative paths are from 3D/).
Needs OpenGL: run from a desktop session, or wrap it in xvfb-run.
EOF
        exit 0
        ;;
    -*) echo "Unknown option: $1 (see --help)" >&2; exit 2 ;;
esac

mkdir -p "$(dirname "$OUT")" || exit 1
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
if ! "$OPENSCAD" -o "$OUT" --imgsize="$SIZE" --camera="$CAMERA" --colorscheme=Tomorrow \
    assembly-preview.scad >"$LOG" 2>&1 || grep -qE "ERROR|Assertion" "$LOG"; then
    grep -E "ERROR|WARNING|Assertion" "$LOG" || tail -5 "$LOG"
    echo "FAILED to render $OUT" >&2
    exit 1
fi
echo "Wrote $(readlink -f "$OUT")"
