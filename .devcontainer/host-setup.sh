#!/usr/bin/env bash
# Runs on the host before the container starts (initializeCommand).
#
# Creates the folders the named volumes mount over. Otherwise Docker creates the missing ones,
# owned by root, in your checkout. Existing ones are left as they are: the container only hides
# them, so a build or venv you have on the host keeps working there.
#
# Usage: .devcontainer/host-setup.sh [-h|--help]
set -eu
case "${1:-}" in
    -h | --help) sed -n '2,8p' "$0" | cut -c3-; exit 0 ;;
esac
cd "$(dirname "$(readlink -f "$0")")/.."
mkdir -p vmoji/build build-host-tests tools/dashboard/.venv
