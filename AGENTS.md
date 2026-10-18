# AGENTS.md

## Layout

- `vmoji/`: RP2040 firmware (C/C++, Pico SDK). Dual-core: core 0 handles commands, telemetry and
  rotation sync; core 1 runs the PIO-paced LED scan.
- `tests/firmware/`: host-side (PC) tests for the firmware logic, no SDK or board needed.
- `tools/dashboard/`: PySide6 telemetry dashboard (see its README).
- `3D/`: OpenSCAD mechanics (see `3D/README.md` for BOM, print and assembly notes).

## Commands

- Host firmware tests:
  `cmake -S tests/firmware -B build-host-tests && cmake --build build-host-tests && ctest --test-dir build-host-tests --output-on-failure`
  A single test: `ctest --test-dir build-host-tests -R <test_name>`.
- Dashboard (from `tools/dashboard`, in its venv): `pytest` and `ruff check`.
- CAD checks: `3D/check-collisions.sh [check ...]`. Slow (minutes); fails on real overlaps or
  failed asserts.
- The firmware itself builds through the Pico VS Code extension's SDK setup, not a plain CLI
  build. Don't expect to compile `vmoji/` standalone.

## Invariants that span files

- Keep logic that must be testable free of the Pico SDK, behind platform hooks, and keep
  hardware-touching code thin. New host tests are registered in `tests/firmware/CMakeLists.txt`.
- The telemetry wire format has two independent implementations (C++ and Python). Change them
  together and keep the shared test vectors passing.
- OpenSCAD parts all derive from one shared params file. The layout asserts and the collision
  script are the safety net: don't weaken or bypass them to make a build pass.
  `3D/archive/` is retired v1 code and not expected to build.
- Coil-safe rule: no metal in the TX-RX coil gap.

## Conventions

- Never delete or strip comments unless explicitly asked. They record design intent, timing
  contracts and past pitfalls. Move them with the code and update them in place when behavior
  changes.
- Mechanical parts are printed in PLA; fit tolerances are tuned with the fit-test coupons, not
  guessed.
