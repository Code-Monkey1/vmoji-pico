# AGENTS.md

Linux-only project. Human documentation lives in [`docs/`](docs); read the relevant guide
before changing an area. Start with [`docs/architecture.md`](docs/architecture.md).

## Layout

- `vmoji/`: RP2040 firmware (C/C++, Pico SDK). Core 0 handles commands, telemetry, rotation
  sync and volume bake, and scans the matrix in static mode. Core 1 runs the PIO-paced scan in
  pov/sim mode. See `docs/firmware.md`.
- `tests/firmware/`: host-side (PC) tests for the firmware logic, no SDK or board needed.
- `tools/dashboard/`: PySide6 telemetry dashboard. See `docs/dashboard.md`.
- `3D/`: OpenSCAD mechanics. See `docs/mechanics.md`, `docs/printing.md`, `docs/assembly.md`.
- `scripts/`: repo-wide helpers. `vmoji/scripts/` and `3D/scripts/` hold area-specific ones.
  Every script has `--help`.

## Commands

- Everything before a commit: `scripts/check.sh` (firmware host tests, dashboard pytest + ruff,
  doc links). Add `--cad` for the slow collision check.
- Setup problems: `scripts/doctor.sh`.
- One host test: `ctest --test-dir build-host-tests -R <test_name>` (after `scripts/check.sh`
  has configured `build-host-tests`).
- Firmware: `vmoji/scripts/build.sh` builds `vmoji/build/vmoji.uf2` from the CLI;
  `vmoji/scripts/flash.sh` flashes it (needs a board). VS Code is optional.
- CAD: `3D/scripts/check-collisions.sh [check ...]` (slow, minutes);
  `3D/scripts/export-stl.sh [part ...]` regenerates the gitignored `3D/stl/`.

## Invariants that span files

- Keep logic that must be testable free of the Pico SDK, behind injected hooks, and keep
  hardware-touching code thin. New sources and host tests are registered in
  `vmoji/CMakeLists.txt` and `tests/firmware/CMakeLists.txt` (see `docs/firmware.md`).
- The telemetry wire format has two implementations (C++ and Python). Change them together:
  regenerate `tools/protocol_vectors.txt` with `tools/update-protocol-vectors.sh` and keep the
  tests passing (`docs/telemetry.md`).
- OpenSCAD parts all derive from one shared params file. The layout asserts and the collision
  script are the safety net: don't weaken or bypass them to make a build pass.
- Coil-safe rule: no metal in the TX-RX coil gap.
- Versions (SDK, toolchain, picotool) are set only in `vmoji/CMakeLists.txt`; scripts read them
  from there.

## Conventions

- Never delete or strip comments unless explicitly asked. They record design intent, timing
  contracts and past pitfalls. Move them with the code and update them in place when behavior
  changes.
- When behavior changes, update the matching page in `docs/` in the same change. In docs, name
  the parameter, constant or file that holds a value instead of copying the value, so the docs
  can't drift from the code.
- Mechanical parts are printed in PLA; fit tolerances are tuned with the fit-test coupons, not
  guessed.
