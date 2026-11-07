#!/usr/bin/env bash
# Regenerate the STLs in 3D/stl/ from the current sources. They come out in modelled orientation:
# orient them in the slicer per docs/printing.md.
#
# With no arguments, every printed part is rendered and the whole stl/ folder is replaced, so stale
# or obsolete files never survive. Parts render into a staging folder next to stl/ first: stl/ is
# only touched if all of them succeed (no ERROR, WARNING or failed assert in the OpenSCAD log).
#
# Usage: 3D/scripts/export-stl.sh [-h|--help] [part ...]   (default: all printed parts; e.g. rotor-head fit-test)
#        Naming parts re-renders just those files and leaves the rest of stl/ alone.
# Env:   OPENSCAD=/path/to/openscad  OPENSCAD_ARGS="..."  JOBS=4
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

OPENSCAD="${OPENSCAD:-openscad}"
OPENSCAD_ARGS="${OPENSCAD_ARGS:-}"
# CGAL renders on OpenSCAD 2021 are RAM-hungry (motor-base): cap the default parallelism.
nproc_n="$(nproc 2>/dev/null || echo 4)"
JOBS="${JOBS:-$((nproc_n < 4 ? nproc_n : 4))}"
OUT_DIR="stl"

# Printed parts (see docs/printing.md). fit-test is left out: coupons are printed
# on demand, picked with its `coupon` parameter; name it explicitly to export the default set.
PARTS=(
    motor-base
    motor-base-lid
    motor-tx-deck
    motor-pinion
    rotor-shaft
    rotor-head
    bearing-spacer
)
EXTRA_PARTS=(fit-test)

usage() {
    cat <<EOF
Usage: 3D/scripts/export-stl.sh [-h|--help] [part ...]

Regenerate 3D/stl/ from the current sources. With no parts, every printed part is rendered and the
whole stl/ folder is replaced. Named parts are re-rendered alone and the rest of stl/ is kept.
stl/ is only touched if every render succeeds (no ERROR, WARNING or failed assert).
STLs keep the modelled orientation: orient them per docs/printing.md.

Printed parts (default): ${PARTS[*]}
On request only:         ${EXTRA_PARTS[*]}
A trailing .scad is accepted (tab completion).

Environment:
  OPENSCAD=/path/to/openscad          OpenSCAD binary (default: openscad)
  OPENSCAD_ARGS="..."                 Extra OpenSCAD flags
  JOBS=N                              Parallel renders (default: min(nproc, 4), here $JOBS)
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h | --help) usage; exit 0 ;;
        -*) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

full=1
if [ "$#" -gt 0 ]; then
    full=0
    requested=()
    for arg in "$@"; do
        p="${arg%.scad}" # Accept tab-completed file names.
        case " ${PARTS[*]} ${EXTRA_PARTS[*]} " in
            *" $p "*) ;;
            *)
                echo "Unknown part: $arg (see --help)" >&2
                exit 2
                ;;
        esac
        case " ${requested[*]:-} " in
            *" $p "*) ;; # Drop duplicates: two jobs would write the same file.
            *) requested+=("$p") ;;
        esac
    done
    PARTS=("${requested[@]}")
fi

# Staging lives next to stl/ (same filesystem), so the final moves are renames.
STAGE="$(mktemp -d "$PWD/.stl-staging.XXXXXX")" || exit 1
chmod 755 "$STAGE" # mktemp makes it 0700; it becomes stl/ itself on a full run.
trap 'rm -rf "$STAGE"' EXIT

render() {
    local p="$1" log="$STAGE/$1.log"
    # shellcheck disable=SC2086
    if "$OPENSCAD" $OPENSCAD_ARGS -o "$STAGE/$p.stl" "$p.scad" >"$log" 2>&1 \
        && ! grep -qE "ERROR|WARNING|Assertion" "$log" \
        && [ -s "$STAGE/$p.stl" ]; then
        echo "ok      $p"
    else
        # One write per part, so parallel jobs don't interleave the lines.
        local why
        why="$(grep -E "ERROR|WARNING|Assertion" "$log" | head -3)"
        [ -n "$why" ] || why="$(tail -3 "$log")"
        printf 'FAILED  %s\n%s\n' "$p" "$(printf '%s\n' "$why" | sed 's/^/        /')"
        rm -f "$STAGE/$p.stl"
        return 1
    fi
}
export -f render
export OPENSCAD OPENSCAD_ARGS STAGE

echo "Rendering ${#PARTS[@]} part(s) with $JOBS job(s)..."
if ! printf '%s\n' "${PARTS[@]}" | xargs -d '\n' -P "$JOBS" -I{} bash -c 'render "$1"' _ {}; then
    echo "FAILED: $OUT_DIR/ left untouched." >&2
    exit 1
fi
rm -f "$STAGE"/*.log

if [ $full -eq 1 ]; then
    # Swap the whole folder: stl/ is either the old set or the complete new one.
    old="$STAGE.old"
    if [ -e "$OUT_DIR" ]; then
        mv "$OUT_DIR" "$old" || exit 1
    fi
    if ! mv "$STAGE" "$OUT_DIR"; then
        [ -e "$old" ] && mv "$old" "$OUT_DIR"
        echo "FAILED to replace $OUT_DIR/." >&2
        exit 1
    fi
    rm -rf "$old"
else
    mkdir -p "$OUT_DIR" || exit 1
    for p in "${PARTS[@]}"; do
        mv "$STAGE/$p.stl" "$OUT_DIR/$p.stl" || { echo "FAILED to write $OUT_DIR/$p.stl" >&2; exit 1; }
    done
fi
echo "Wrote ${#PARTS[@]} STL(s) to 3D/$OUT_DIR/."
