#!/usr/bin/env bash
# Run every collision / soldering-iron check in collision-check.scad and fail if any
# intersection has a real volume. Touching faces (zero volume) are OK.
#
# Checks run in parallel, each in its own OpenSCAD process with its own files, so they can't
# affect each other. The result fails closed: every check must leave a result file saying it is
# clean, so a killed worker (out of memory, for instance) fails the run instead of passing.
#
# Usage: 3D/scripts/check-collisions.sh [-h|--help] [check ...]      (default: all checks)
# Env:   OPENSCAD=/path/to/openscad  THRESHOLD_MM3=0.5  OPENSCAD_ARGS="..."  JOBS=4
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

OPENSCAD="${OPENSCAD:-openscad}"
THRESHOLD_MM3="${THRESHOLD_MM3:-0.5}"
OPENSCAD_ARGS="${OPENSCAD_ARGS:-}"
# One job per core, within one per GB of free memory: the largest check peaks under 1 GB
# (OpenSCAD 2021). Running out of memory couldn't pass anyway, it would only fail the run.
nproc_n="$(nproc 2>/dev/null || echo 4)"
mem_gb="$(awk '/MemAvailable/ {print int($2 / 1048576)}' /proc/meminfo 2>/dev/null)"
mem_gb="${mem_gb:-4}"
[ "$mem_gb" -lt 1 ] && mem_gb=1
JOBS="${JOBS:-$((nproc_n < mem_gb ? nproc_n : mem_gb))}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

CHECKS=(
    base_deck base_lid deck_lid
    base_motors base_pinions base_rotor
    deck_rotor deck_pinions lid_rotor
    motors_rotor motors_pinions
    bearings_base bearings_deck bearings_rotor
    stud_rotor stud_base stud_deck
    head_rotor coils ir_parts ir_sweep
    base_jack base_switch jack_switch
    iron_columns iron_posts iron_head
)
INFO_CHECKS=(mesh)

usage() {
    cat <<EOF
Usage: 3D/scripts/check-collisions.sh [-h|--help] [check ...]

Run the collision / soldering-iron checks in collision-check.scad (default: all of them) and fail
if any intersection has a real volume (> THRESHOLD_MM3). Touching faces are OK. Takes minutes.
Rows appear as checks finish, so their order varies.

Checks:
$(printf '%s ' "${CHECKS[@]}" | fold -s -w 92 | sed 's/^/  /')
Info only (full run): ${INFO_CHECKS[*]}

Environment:
  OPENSCAD=/path/to/openscad          OpenSCAD binary (default: openscad)
  THRESHOLD_MM3=0.5                   Largest overlap volume still counted as touching
  OPENSCAD_ARGS="..."                 Extra OpenSCAD flags
  JOBS=N                              Parallel renders (default: one per core, at most one per
                                      GB of free memory; here $JOBS)
EOF
}

for arg in "$@"; do
    case "$arg" in
        -h | --help) usage; exit 0 ;;
        -*) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

if [ "$#" -gt 0 ]; then
    # An unknown check name renders nothing in collision-check.scad and would pass as "ok".
    requested=()
    for arg in "$@"; do
        case " ${CHECKS[*]} ${INFO_CHECKS[*]} " in
            *" $arg "*) ;;
            *) echo "Unknown check: $arg (see --help)" >&2; exit 2 ;;
        esac
        case " ${requested[*]:-} " in
            *" $arg "*) ;; # Drop duplicates: two jobs would write the same files.
            *) requested+=("$arg") ;;
        esac
    done
    CHECKS=("${requested[@]}")
    INFO_CHECKS=()
fi

# Signed volume of an ASCII or binary STL (mm^3).
stl_volume() {
    python3 - "$1" <<'PY'
import struct, sys
path = sys.argv[1]
data = open(path, "rb").read()
tris = []
if data[:5] == b"solid" and b"facet" in data[:512]:
    verts = []
    for line in data.decode(errors="ignore").splitlines():
        p = line.split()
        if p and p[0] == "vertex":
            verts.append(tuple(map(float, p[1:4])))
    tris = [verts[i:i + 3] for i in range(0, len(verts) - 2, 3)]
else:
    n = struct.unpack_from("<I", data, 80)[0]
    for i in range(n):
        v = struct.unpack_from("<12f", data, 84 + i * 50)
        tris.append([v[3:6], v[6:9], v[9:12]])
vol = 0.0
for a, b, c in tris:
    vol += (a[0] * (b[1] * c[2] - b[2] * c[1])
            - a[1] * (b[0] * c[2] - b[2] * c[0])
            + a[2] * (b[0] * c[1] - b[1] * c[0])) / 6.0
print(f"{abs(vol):.3f}")
PY
}

# Prints the volume, or ERROR and the reason on the lines after it.
run_one() {
    local name="$1" out="$TMP/$1.stl" log="$TMP/$1.log"
    # shellcheck disable=SC2086
    "$OPENSCAD" $OPENSCAD_ARGS -D "check=\"$name\"" -o "$out" collision-check.scad >"$log" 2>&1
    local rc=$?
    if grep -qE "ERROR|Assertion" "$log"; then
        echo "ERROR"
        grep -E "ERROR|Assertion" "$log" | head -3
        return
    fi
    # An empty intersection exits 1 and writes no STL (OpenSCAD 2021), so only trust "empty" when
    # the log says so: a missing/crashed OpenSCAD must not pass as "no collision".
    if grep -q "Current top level object is empty" "$log"; then
        echo "0.000"
        return
    fi
    if [ $rc -ne 0 ] || [ ! -s "$out" ]; then
        echo "ERROR"
        tail -3 "$log"
        return
    fi
    stl_volume "$out" || echo "ERROR"
}

# One worker: render a check, print its row, and write "ok" as the check's last act. Anything
# else, or no file at all, counts as a failure when the results are collected below.
run_check() {
    local name="$1" kind="$2" output v row
    output="$(run_one "$name")"
    v="$(printf '%s\n' "$output" | head -1)"
    if [ "$kind" = "info" ]; then
        row="$(printf "%-16s %12s  %s" "$name" "$v" "info (gear tooth overlap at rotor angle 0)")"
        [ "$v" = "ERROR" ] && row="$row
$(printf '%s\n' "$output" | tail -n +2)"
    elif ! printf '%s' "$v" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
        row="$(printf "%-16s %12s  %s\n%s" "$name" "-" "ERROR" "$(printf '%s\n' "$output" | tail -n +2)")"
    elif python3 -c "import sys; sys.exit(0 if float('$v') <= float('$THRESHOLD_MM3') else 1)"; then
        row="$(printf "%-16s %12s  %s" "$name" "$v" "ok")"
        echo "ok" >"$TMP/$name.result"
    else
        row="$(printf "%-16s %12s  %s" "$name" "$v" "COLLISION")"
    fi
    # One write per check, so parallel jobs don't interleave their lines.
    printf '%s\n' "$row"
}
export -f stl_volume run_one run_check
export OPENSCAD OPENSCAD_ARGS THRESHOLD_MM3 TMP

printf "%-16s %12s  %s\n" "check" "volume mm3" "result"
{
    for c in "${CHECKS[@]}"; do printf '%s check\n' "$c"; done
    [ ${#INFO_CHECKS[@]} -gt 0 ] && for c in "${INFO_CHECKS[@]}"; do printf '%s info\n' "$c"; done
} | xargs -P "$JOBS" -L 1 bash -c '(run_check "$1" "$2"); exit 0' _
# The subshell and "exit 0": xargs stops everything when a worker dies by a signal, leaving the
# other renders running, and the collection below already counts a dead worker as a failure.

failed=()
for c in "${CHECKS[@]}"; do
    [ "$(cat "$TMP/$c.result" 2>/dev/null)" = "ok" ] || failed+=("$c")
done
if [ ${#failed[@]} -ne 0 ]; then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "All collision checks passed."
