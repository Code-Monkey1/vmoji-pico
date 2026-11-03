# Bring-up

A checklist for a freshly flashed or freshly assembled board. Work through it top to
bottom; each section assumes the previous one passed.

Send commands with `verify_link.py` from `tools/dashboard` (see [Commands](commands.md)).
In this page, `send X` is short for:

```bash
.venv/bin/python verify_link.py --port /dev/ttyACM0 --command "X"
```

## 0. Link

1. Power the Pico over USB. With no host attached, the **boot demo** walks every LED
   alone, row by row, and loops. That shows the board is alive.
2. `verify_link.py --port /dev/ttyACM0` (no command) must print `PASS`. If not, see
   [Troubleshooting](troubleshooting.md).

## 1. Static display

1. `send "G 1"`: the boot demo stops and the heart glyph appears, upright.
2. `send "S 2 3"`: the score digits appear and the activity pixel blinks.
3. `send "P"`: the display blanks and stays blank. The board must **not** reset (that
   would mean the watchdog fired). `send "P"` again resumes.
4. **Orientation:** run the pixel walk (dashboard *Pixel walk* panel, or
   `walk_pixels.py --port /dev/ttyACM0 --step`). The first LED (`r0 c0`) must be the
   physical top-left, then left to right and row by row downwards. If not, fix
   `board_row_pins()` in [`vmoji/board_pins.h`](../vmoji/board_pins.h).

## 2. Simulated POV (no spinning needed)

1. `send "M sim"`, then `send "V 1"` (the asymmetric L).
2. `send "?"`: expect `mode=sim`, with `rpm` and `period` at the fixed simulated rate
   (`ROTATION_SIM_RPM`, `ROTATION_SIM_PERIOD_US` in
   [`vmoji/rotation_sync.h`](../vmoji/rotation_sync.h)).
3. On a stationary board the slices blur together, but the lit rows should be the bottom
   ones (the L's foot) plus the top one (a marker voxel). Upside down means the row/height
   flip in [`vmoji/geometry.h`](../vmoji/geometry.h) is wrong for this mount.
4. Optional, with a logic analyzer on a column GPIO: blank, settle
   (`MATRIX_BLANK_SETTLE_US`), then lit dwell, repeating once per mux step. A step lasts
   one turn divided by the steps per turn (`CODEC_WEIGHT_SUM` × `ANGULAR_SLICES`).

## 3. Real IR sync

1. Wire the IR receiver to **GP13** (`INDEX_IR_GPIO`). The input has an internal pull-up and
   triggers on the falling edge.
2. `send "M pov"`, `send "V 1"`, then spin the rotor (or pulse GP13 once per turn).
3. `send "?"`: `rpm` follows the real speed without jumping around. Contact bounce shorter
   than `IR_REFRACTORY_US` is ignored.
4. The L should look locked in space, not smeared, and upright: foot at the bottom, marker
   at the top. Note which side it appears on and which way its foot points as the angle
   grows; the angular direction and the +radius side have not been verified on a spinning
   rotor yet.
5. Stop the pulses: within `ROT_EST_SYNC_LOSS_US` the display blanks.
6. The dashboard's *Flags* readout must not show `FIFO OVF` during normal operation.

## 4. Regression checks

- `send "M static"` returns to the static display.
- `send "V 0"` and `send "V 2"` switch to the cube and index-bar volumes (pov/sim).
- Bad input is rejected with an `ERR …` reply: `M nope`, `V 9`, `M simulate`.
