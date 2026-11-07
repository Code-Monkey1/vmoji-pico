#!/usr/bin/env bash
# Run the repo's checks: what to run before you commit.
#
# Usage: scripts/check.sh [-h|--help] [--cad]
set -u
set -o pipefail
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

cad=0
for arg in "$@"; do
    case "$arg" in
        -h | --help)
            cat <<EOF
Usage: scripts/check.sh [-h|--help] [--cad]

Runs, in order, and reports each:
  1. Firmware host tests (CMake + CTest in build-host-tests/, no board needed)
  2. Dashboard tests and lint (pytest + ruff, in tools/dashboard/.venv)
  3. Doc links (every relative link in README.md, AGENTS.md and docs/ must exist)
  4. The collision check's verdicts, against a fake OpenSCAD (seconds; no real render)
  --cad   5. CAD collision check (3D/scripts/check-collisions.sh, several minutes)
Exits 1 if any step fails. Missing tools? Run scripts/doctor.sh.
EOF
            exit 0
            ;;
        --cad) cad=1 ;;
        *) echo "Unknown argument: $arg (see --help)" >&2; exit 2 ;;
    esac
done

failed=()
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT

# step <name> <command...>: full output goes to a log. A passing step shows its last
# line; a failing one shows the end of the log, which is where the reason is.
step() {
    local name="$1"
    shift
    echo "==> $name"
    if "$@" >"$LOG" 2>&1; then
        local summary
        summary="$(grep -E 'passed|ok' "$LOG" | tail -1)"
        echo "    ok: ${summary:-$(grep -v '^[[:space:]]*$' "$LOG" | tail -1)}"
    else
        tail -40 "$LOG" | sed 's/^/    /'
        echo "    FAILED: $name"
        failed+=("$name")
    fi
}

host_tests() {
    cmake -S tests/firmware -B build-host-tests &&
        cmake --build build-host-tests &&
        ctest --test-dir build-host-tests --output-on-failure
}

dashboard() {
    local py=tools/dashboard/.venv/bin/python
    if [ ! -x "$py" ]; then
        echo "    No dashboard venv. Create it (docs/getting-started.md):"
        echo "    cd tools/dashboard && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt"
        return 1
    fi
    (cd tools/dashboard && .venv/bin/python -m pytest tests -q && .venv/bin/ruff check .)
}

step "Firmware host tests" host_tests
step "Dashboard tests and lint" dashboard
step "Doc links" python3 scripts/check-doc-links.py
step "Collision check verdicts" 3D/scripts/test-check-collisions.sh
[ $cad -eq 1 ] && step "CAD collision check" 3D/scripts/check-collisions.sh

echo
if [ ${#failed[@]} -gt 0 ]; then
    echo "FAILED: ${failed[*]}"
    exit 1
fi
echo "All checks passed."
