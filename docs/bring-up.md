# Bring-up

A checklist for a freshly flashed or freshly assembled board. Work through it top to
bottom; each section assumes the previous one passed.

Send commands with `verify_link.py` from `tools/dashboard` (see [Commands](commands.md)).
In this page, `send X` is short for:

```bash
.venv/bin/python verify_link.py --port /dev/ttyACM0 --command "X"
```

If the board isn't `/dev/ttyACM0`, `.venv/bin/python app.py --list-ports` shows its name.

## 0. Link

1. Power the Pico over USB. With no host attached, the **boot demo** walks every LED
   alone, row by row, and loops. That shows the board is alive.
2. `verify_link.py --port /dev/ttyACM0` (no command) must print `PASS`. If not, see
   [Troubleshooting](troubleshooting.md).

## 1. Static display

1. `send "G 1"`: the boot demo stops and the heart glyph appears, upright.
2. `send "S 2 3"`: the score digits appear and the activity pixel (bottom right) blinks.
3. `send "P"`: the display blanks and stays blank. The board must **not** reset (that
   would mean the watchdog fired). `send "P"` again resumes.
4. **Orientation:** run the pixel walk (dashboard *Pixel walk* panel, or
   `walk_pixels.py --port /dev/ttyACM0 --step`). The first LED (`r0 c0`) must be the
   physical top-left, then left to right and row by row downwards. If not, fix the order in
   [`vmoji/board_pins.h`](../vmoji/board_pins.h): `board_row_pins()` if it's upside down,
   `board_col_pins()` if it's mirrored.

## 2. Simulated POV (no spinning needed)

1. `send "M sim"`, then `send "V 1"` (the asymmetric L).
2. `send "?"`: expect `mode=sim`, with `rpm` and `period` at the fixed simulated rate
   (`ROTATION_SIM_RPM`, `ROTATION_SIM_PERIOD_US` in
   [`vmoji/rotation_sync.h`](../vmoji/rotation_sync.h)).
3. On a stationary board the slices blur together, but the lit rows should be the bottom
   ones (the L's foot) plus the top one (a marker voxel). Upside down means the row/height
   flip, `geometry_row_to_z()` in [`vmoji/geometry.h`](../vmoji/geometry.h), is wrong for this
   mount.
4. Optional, with a logic analyzer on a column GPIO: blank, settle
   (`MATRIX_BLANK_SETTLE_US`), then lit dwell, repeating once per mux step. A step lasts
   one turn divided by the steps per turn (`CODEC_WEIGHT_SUM` × `ANGULAR_SLICES`).

## 3. Real IR sync

The cable carries the data, so the rotor can't spin at speed during these steps. You make the
index pulses by hand instead, and watch the *Flags* and *Rotor speed* readouts in the dashboard.
Send the commands first, then open the dashboard: two programs reading one port take bytes from
each other, and the mode stays set when `send` exits.

1. Wire the IR receiver to **GP13** (`INDEX_IR_GPIO`). The input has an internal pull-up and
   triggers on the falling edge. Power the IR LED.
2. `send "M pov"`, `send "V 1"`.
3. Make pulses: turn the base slowly by hand (mind the cable), or pass a pencil through the IR
   beam in a steady rhythm. Each pulse should light `SYNC OK` for a moment and flash the
   display, whose image means nothing at this speed. No flash at all points to the wiring or
   the beam's alignment. Contact bounce shorter than `IR_REFRACTORY_US` is ignored.
4. Read the rotor speed, knowing how the firmware treats slow pulses:
   - gaps longer than `ROT_EST_SYNC_LOSS_US` drop sync, so `SYNC OK` flickers instead of
     staying on, and the display blanks between pulses;
   - gaps longer than `ROT_EST_MAX_PERIOD_US` don't count towards the speed, so it stays at its
     starting value, `ROTATION_SIM_RPM`. The readout flashes that number between "no sync"
     warnings, and the plot draws it. **It is not a measurement.**

   The limits are in [`vmoji/rotation_estimator.h`](../vmoji/rotation_estimator.h). For a real
   rpm, the pencil has to beat the second limit in a steady rhythm.
5. Stop the pulses: within `ROT_EST_SYNC_LOSS_US` the display blanks and `SYNC OK` goes out.
6. The dashboard's *Flags* readout must not show `FIFO OVF` during normal operation.

**At full speed (not tried yet).** The check is that the L looks locked in space, not smeared,
and upright: foot at the bottom, marker at the top, noting which side it appears on and which
way its foot points as the angle grows (the angular direction and the +radius side have not been
verified on a spinning rotor yet). The board boots in `static` and doesn't save its mode, so it
has to stay powered from `M pov` until it's spinning: send `M pov` and `V 1` with the RX coil
already powering it, unplug the cable, then spin up. Any power loss on the way returns it to
`static`.

## 4. Regression checks

- `send "M static"` returns to the static display.
- `send "V 0"` and `send "V 2"` switch to the cube and index-bar volumes (pov/sim).
- Bad input is rejected with an `ERR …` reply: `M nope`, `V 9`, `M simulate`.
