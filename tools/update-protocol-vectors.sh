#!/usr/bin/env bash
# Regenerate tools/protocol_vectors.txt from the C++ telemetry implementation.
#
# Run this after changing vmoji/telemetry_frame.h (or the sample values in
# tools/protocol_selftest.cpp), then update tools/dashboard/protocol.py until the
# Python tests pass. The `protocol_vectors_current` ctest fails until you do.
set -u
cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

usage() {
    cat <<USAGE
Usage: tools/update-protocol-vectors.sh [-h|--help]

Builds tools/protocol_selftest.cpp with the host C++ compiler (\$CXX, default g++),
runs its self-checks, and writes its --vectors output to tools/protocol_vectors.txt.
USAGE
}

case "${1:-}" in
    -h | --help) usage; exit 0 ;;
    "") ;;
    *) echo "Unknown argument: $1 (see --help)" >&2; exit 2 ;;
esac

CXX="${CXX:-g++}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

"$CXX" -std=c++17 -Wall -Wextra -I vmoji tools/protocol_selftest.cpp -o "$TMP/selftest" || exit 1
"$TMP/selftest" >"$TMP/checks.log" || { cat "$TMP/checks.log"; echo "Self-checks failed." >&2; exit 1; }
"$TMP/selftest" --vectors >tools/protocol_vectors.txt || exit 1
echo "Wrote tools/protocol_vectors.txt. Now run the dashboard tests (scripts/check.sh)."
