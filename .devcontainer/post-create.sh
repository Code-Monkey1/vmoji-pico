#!/usr/bin/env bash
# Runs inside the container once, after it is created (postCreateCommand): creates the dashboard's
# venv, then checks the setup.
#
# Usage: .devcontainer/post-create.sh [-h|--help]
set -eu
case "${1:-}" in
    -h | --help) sed -n '2,5p' "$0" | cut -c3-; exit 0 ;;
esac
cd "$(dirname "$(readlink -f "$0")")/.."

(
    cd tools/dashboard
    [ -x .venv/bin/python ] || python3 -m venv .venv
    .venv/bin/pip install --quiet -r requirements.txt
)

scripts/doctor.sh
