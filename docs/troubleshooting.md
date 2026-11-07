# Troubleshooting

Start with `scripts/doctor.sh`: it finds most setup problems and prints the fix.

## Firmware

**`No Pico SDK at ...`**
Run `vmoji/scripts/setup-sdk.sh`, or point `PICO_SDK_PATH` at an existing SDK checkout.

**`No picotool with USB support found`**
Run `vmoji/scripts/setup-sdk.sh`, which builds one
([why it's separate](getting-started.md#3-firmware-the-pico-sdk-and-picotool)).

**Flashing fails: no device found, or permission denied**
- Use a data USB cable; some cables only charge.
- Install the udev rule from [Getting started](getting-started.md#6-access-to-the-board-over-usb).
- A blank or crashed board can't be rebooted remotely: hold BOOTSEL while plugging it in,
  then flash again (or copy the UF2 onto the `RPI-RP2` drive).

**CMake complains about the generator or the cache**
The build folder was created by a different setup. Start over with
`vmoji/scripts/build.sh --clean`.

**`flash.sh` fails in the dev container, and the board is now in BOOTSEL**
That's expected when flashing a running board from the container. Run `flash.sh` again
([why](getting-started.md#the-quick-way-a-dev-container)).

**The dev container finds no board, or permission is denied**
Install the udev rule on the host, not in the container, and replug the board
([Getting started](getting-started.md#6-access-to-the-board-over-usb)).

**A change to `.devcontainer/` has no effect**
Zed doesn't rebuild on its own. Stop the container (`docker ps`, then `docker rm -f <name>`) and
reopen the project.

**The desktop says it can't find or mount `RPI-RP2`**
Harmless while flashing. In BOOTSEL the board appears as a drive of that name, and the drive goes
away when the board reboots, which can happen before the desktop finishes opening it.

## Serial link and dashboard

**`Permission denied: '/dev/ttyACM0'`**
Join the `dialout` group, then log out and back in:
`sudo usermod -aG dialout $USER`.

**The port exists but no telemetry arrives**
- Run `verify_link.py --port /dev/ttyACM0` (from `tools/dashboard`): it names the problem
  in one line.
- On Ubuntu, ModemManager sometimes grabs new serial ports for a few seconds after
  plug-in. Wait, or stop it: `sudo systemctl stop ModemManager`.
- On UART, check that TX and RX are crossed (board GP0 TX → adapter RX).

**The dashboard shows the SIMULATION banner**
It found no board that sends valid frames. Check the cable, the `dialout` group and that
the board runs vmoji (`verify_link.py`). Pick the port by hand with `--port`.

**`No display: the dashboard needs a graphical session`**
There is no desktop session here (SSH, a container). See
[Dashboard: no display](dashboard.md#no-display).

**`qt.qpa.plugin: Could not load the Qt platform plugin "xcb"`**
You do have a display, and a library Qt needs is missing: `sudo apt install libxcb-cursor0`.

**`could not connect to display` in the dev container**
The host hasn't allowed it: see the `xhost` command in
[Getting started](getting-started.md#the-quick-way-a-dev-container).

**A serial terminal shows garbage**
That is expected: command replies travel inside the binary telemetry stream. Use
`verify_link.py --command` or the dashboard ([Commands](commands.md)).

## 3D

**`Can't open library 'BOSL2/std.scad'`**
Install BOSL2 ([Getting started](getting-started.md#5-3d-the-bosl2-library)).

**The collision check reports `ERROR` instead of a volume**
OpenSCAD failed to render that check; the lines printed under it give the reason (often a
failed assert after a parameter change). Run the check alone to iterate faster, for example
`3D/scripts/check-collisions.sh coils`.

**`export-stl.sh` reports `FAILED` and leaves `stl/` untouched**
A part failed to render or raised a warning. The lines under `FAILED` show why; open that
part in OpenSCAD to see it in context.

**`render-preview.sh` fails without a display**
OpenSCAD needs OpenGL to write PNGs. The script uses a virtual display on its own when
`xvfb-run` is installed: `sudo apt install xvfb`.
