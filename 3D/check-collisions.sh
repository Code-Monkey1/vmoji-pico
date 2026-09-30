#!/usr/bin/env bash
# Run every collision / soldering-iron check in collision-check.scad and fail if any
# intersection has a real volume. Touching faces (zero volume) are OK.
#
# Usage: ./check-collisions.sh [check ...]      (default: all checks)
# Env:   OPENSCAD=/path/to/openscad  THRESHOLD_MM3=0.5  OPENSCAD_ARGS="--enable=manifold"
set -u
cd "$(dirname "$0")"

OPENSCAD="${OPENSCAD:-openscad}"
THRESHOLD_MM3="${THRESHOLD_MM3:-0.5}"
OPENSCAD_ARGS="${OPENSCAD_ARGS:-}"
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
    iron_columns iron_posts iron_head
)
INFO_CHECKS=(mesh)

if [ "$#" -gt 0 ]; then
    CHECKS=("$@")
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

run_one() {
    local name="$1" out="$TMP/$1.stl" log="$TMP/$1.log"
    # shellcheck disable=SC2086
    "$OPENSCAD" $OPENSCAD_ARGS -D "check=\"$name\"" -o "$out" collision-check.scad >"$log" 2>&1
    local rc=$?
    if grep -qE "ERROR|Assertion" "$log"; then
        echo "ERROR"
        grep -E "ERROR|Assertion" "$log" | head -3 >&2
        return
    fi
    if grep -q "Current top level object is empty" "$log" || [ ! -s "$out" ]; then
        echo "0.000"
        return
    fi
    if [ $rc -ne 0 ]; then
        echo "ERROR"
        tail -3 "$log" >&2
        return
    fi
    stl_volume "$out"
}

fail=0
printf "%-16s %12s  %s\n" "check" "volume mm3" "result"
for c in "${CHECKS[@]}"; do
    v="$(run_one "$c")"
    if [ "$v" = "ERROR" ]; then
        printf "%-16s %12s  %s\n" "$c" "-" "ERROR"
        fail=1
    elif python3 -c "import sys; sys.exit(0 if float('$v') <= float('$THRESHOLD_MM3') else 1)"; then
        printf "%-16s %12s  %s\n" "$c" "$v" "ok"
    else
        printf "%-16s %12s  %s\n" "$c" "$v" "COLLISION"
        fail=1
    fi
done
for c in "${INFO_CHECKS[@]}"; do
    v="$(run_one "$c")"
    printf "%-16s %12s  %s\n" "$c" "$v" "info (gear tooth overlap at rotor angle 0)"
done

if [ $fail -ne 0 ]; then
    echo "FAILED: see COLLISION / ERROR rows above."
    exit 1
fi
echo "All collision checks passed."
