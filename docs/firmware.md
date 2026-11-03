# Firmware

The firmware in [`vmoji/`](../vmoji) targets a Raspberry Pi Pico (RP2040, `PICO_BOARD
pico`) and builds with the Pico SDK. For how it works, read [Architecture](architecture.md)
first. Setup: [Getting started](getting-started.md).

## Build

```bash
vmoji/scripts/build.sh            # configure (first time) and build
vmoji/scripts/build.sh --clean    # start from scratch
```

The output is `vmoji/build/vmoji.uf2`. The SDK, toolchain and picotool versions are pinned
in [`vmoji/CMakeLists.txt`](../vmoji/CMakeLists.txt) (`sdkVersion`, `toolchainVersion`,
`picotoolVersion`). The scripts read them from there.

Without the script, it is plain CMake (with the VS Code extension installed, its SDK is
used whatever `PICO_SDK_PATH` says):

```bash
cmake -S vmoji -B vmoji/build -G Ninja -DPICO_SDK_PATH=$HOME/.pico-sdk/sdk/<version>
cmake --build vmoji/build
```

## Flash

```bash
vmoji/scripts/flash.sh
```

This loads the UF2 with `picotool` and starts it. A board that is running vmoji reboots
into its bootloader on its own; a blank or crashed board needs the BOOTSEL button held while
you plug it in. Without picotool, hold BOOTSEL while plugging in and copy
`vmoji/build/vmoji.uf2` onto the `RPI-RP2` drive that appears.

After flashing, check the board with the [Bring-up](bring-up.md) checklist.

## Test

The logic runs on your PC, no board needed:

```bash
scripts/check.sh                  # everything: firmware, dashboard, docs
```

Or the firmware tests alone:

```bash
cmake -S tests/firmware -B build-host-tests
cmake --build build-host-tests
ctest --test-dir build-host-tests --output-on-failure    # add -R <name> for one test
```

## Code map

| Area | Files | Notes |
|------|-------|-------|
| Entry point | `main.c` | Wiring and the core-0 loop only |
| Pins | `board_pins.h`, `led-matrix.h` | The single source of truth for GPIO assignments |
| Static display | `matrix.c`, `boot_demo.c` | Row scan, glyphs, scores, boot animation |
| POV content | `volume.c`, `volumes_builtin.c`, `geometry.h` | Voxels, built-in shapes, voxel → matrix mapping |
| POV scan | `volume_codec.c`, `pio_scan.c`, `pio_scan.pio`, `scan_timing.c` | Bake, PIO-paced output, step timing |
| POV control | `pov_service.c`, `pov_runtime.c`, `core1_cmd.h` | Core-0 state machine, multicore/PIO glue, core-1 commands |
| Rotation | `rotation_sync.c`, `rotation_estimator.c`, `ir_debounce.c` | IR index, period estimate, debounce |
| Host link | `commands.c`, `uart_link.c`, `telemetry.cpp`, `telemetry_frame.h`, `telemetry_flags.h` | [Commands](commands.md), [Telemetry](telemetry.md) |

## Conventions

- **Testable logic stays free of the Pico SDK.** It receives hardware access through
  injected structs (for example `CommandsDeps` in `commands.h`, `PovPlatform` in
  `pov_service.h`). SDK-only includes and code in a shared file sit behind
  `#ifndef VMOJI_HOST_TEST`.
- **Hardware code stays thin**: `main.c`, `pov_runtime.c`, `pio_scan.c`, `matrix.c`,
  `uart_link.c` and `rotation_sync.c` are not compiled for the host.
- **Comments are part of the code.** They record timing contracts and past pitfalls: move
  them with the code and update them when behavior changes.

### Adding a source file

1. Add it to `add_executable(vmoji ...)` and to the `-Wall;-Wextra` list in
   [`vmoji/CMakeLists.txt`](../vmoji/CMakeLists.txt).
2. If it is SDK-free logic, also add it to `vmoji_host_core` in
   [`tests/firmware/CMakeLists.txt`](../tests/firmware/CMakeLists.txt), then add a test
   with `vmoji_add_test(<name> unit/<file>.c)`.

### Changing the telemetry format

See [Telemetry: changing the format](telemetry.md#changing-the-format). The C++ and Python
sides must change together, and the tests enforce it.
