#!/usr/bin/env bash
# Test check-collisions.sh's verdicts against a fake OpenSCAD: no real render, so it takes seconds.
# The script is the safety net for the printed parts, so it must never pass on a failure.
#
# Usage: 3D/scripts/test-check-collisions.sh [-h|--help]
set -u
case "${1:-}" in
    -h | --help)
        cat <<EOF
Usage: 3D/scripts/test-check-collisions.sh [-h|--help]

Runs check-collisions.sh with a fake OpenSCAD for each outcome (clean, collision, assert, crash,
killed worker) and checks its verdict and exit code. scripts/check.sh runs this.
EOF
        exit 0
        ;;
    "") ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

SCRIPT="$(dirname "$(readlink -f "$0")")/check-collisions.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The fake: behaves as FAKE_<check> says, and renders nothing (an empty intersection) otherwise.
cat >"$WORK/openscad" <<'EOF'
#!/usr/bin/env bash
while [ $# -gt 0 ]; do
    case "$1" in
        -D) check="${2#check=\"}"; check="${check%\"}"; shift ;;
        -o) out="$2"; shift ;;
    esac
    shift
done
behavior="$(printenv "FAKE_$check")"
case "$behavior" in
    collide)
        # A closed tetrahedron with a real volume (1000 / 6 mm^3).
        cat >"$out" <<STL
solid fake
facet normal 0 0 0
outer loop
vertex 0 0 0
vertex 10 0 0
vertex 0 10 0
endloop
endfacet
facet normal 0 0 0
outer loop
vertex 0 0 0
vertex 0 10 0
vertex 0 0 10
endloop
endfacet
facet normal 0 0 0
outer loop
vertex 0 0 0
vertex 0 0 10
vertex 10 0 0
endloop
endfacet
facet normal 0 0 0
outer loop
vertex 10 0 0
vertex 0 0 10
vertex 0 10 0
endloop
endfacet
endsolid fake
STL
        exit 0
        ;;
    assert) echo "ERROR: Assertion 'vm_coil_gap' failed"; exit 1 ;;
    crash) echo "Segmentation fault"; exit 139 ;;
    silent) exit 1 ;;
    no-output) exit 0 ;;
    # Kill the worker itself: our parent is only run_one's subshell, one level below it.
    kill-worker) kill -9 "$(ps -o ppid= -p "$PPID")"; exit 1 ;;
    *) echo "Current top level object is empty."; exit 1 ;;
esac
EOF
chmod +x "$WORK/openscad"

fail=0
# expect <name> <exit code> <text in the output> [FAKE_x=behavior ...] -- <checks>
expect() {
    local name="$1" want_rc="$2" want_text="$3" output rc
    shift 3
    local vars=()
    while [ "$1" != "--" ]; do vars+=("$1"); shift; done
    shift
    output="$(env OPENSCAD="$WORK/openscad" JOBS=4 "${vars[@]}" "$SCRIPT" "$@" 2>&1)"
    rc=$?
    if [ $rc -eq "$want_rc" ] && printf '%s' "$output" | grep -q -- "$want_text"; then
        echo "ok      $name"
    else
        echo "FAILED  $name: exit $rc (wanted $want_rc), wanted the text '$want_text'. Output:"
        printf '%s\n' "$output" | sed 's/^/        /'
        fail=1
    fi
}

expect "all clean passes" 0 "All collision checks passed" -- coils base_deck base_lid
expect "a collision fails" 1 "FAILED: coils" FAKE_coils=collide -- coils base_deck
expect "the volume is measured" 1 "166.667  COLLISION" FAKE_coils=collide -- coils
expect "under the threshold is touching" 0 "166.667  ok" FAKE_coils=collide THRESHOLD_MM3=200 -- coils
expect "a failed assert fails" 1 "Assertion" FAKE_coils=assert -- coils base_deck
expect "a crash fails" 1 "FAILED: coils" FAKE_coils=crash -- coils base_deck
expect "exit 1 with no log fails" 1 "FAILED: coils" FAKE_coils=silent -- coils
expect "success with no STL fails" 1 "FAILED: coils" FAKE_coils=no-output -- coils
# "$": the other check still ran and passed, so only the killed one is listed.
expect "a killed worker fails alone" 1 "FAILED: coils$" FAKE_coils=kill-worker -- coils base_deck
expect "a full run passes" 0 "All collision checks passed" --
expect "a full run finds a failure" 1 "FAILED: iron_head" FAKE_iron_head=collide --
expect "a crashed info check is reported" 0 "Segmentation fault" FAKE_mesh=crash --
expect "a crashed info check doesn't fail the run" 0 "All collision checks passed" FAKE_mesh=crash --
expect "one failure among many is found" 1 "FAILED: iron_head" FAKE_iron_head=collide -- \
    base_deck base_lid deck_lid base_motors base_pinions iron_head coils ir_parts
expect "a missing OpenSCAD fails" 1 "FAILED: coils" OPENSCAD=/nonexistent/openscad -- coils
expect "an unknown check is refused" 2 "Unknown check" -- not_a_check

if [ $fail -ne 0 ]; then
    echo "FAILED: check-collisions.sh gave a wrong verdict."
    exit 1
fi
echo "All check-collisions.sh verdicts are right."
