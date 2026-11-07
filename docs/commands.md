# Commands

The board accepts short ASCII command lines on USB and on UART0. Each line is one letter,
optionally followed by arguments, ending in `\n` (`\r` is ignored). The grammar is defined
in [`vmoji/commands.h`](../vmoji/commands.h), which wins if this page ever disagrees.

## Sending commands

Replies come back inside the binary telemetry stream, so a plain serial terminal shows
them mixed with binary noise. Use one of these instead:

```bash
cd tools/dashboard
.venv/bin/python verify_link.py --port /dev/ttyACM0 --command "?"      # one command
.venv/bin/python app.py                                                # the dashboard
```

The dashboard's control panel sends the common commands and logs every reply.

## Reference

| Command | Effect | Reply |
|---------|--------|-------|
| `S <0-9> <0-9>` | Show two score digits | `OK 2-3` |
| `H` | Heartbeat: blink the activity pixel | `OK heartbeat` |
| `G <id>` | Show a glyph (`id` from 0 to `GLYPH_COUNT`−1, in `matrix.h`) | `OK glyph 1` |
| `X <row> <col>` | Light one pixel alone (soldering check) | `OK pixel r3 c5 row=GP… col=GP…` |
| `D <us>` | Static-mode row dwell (`DWELL_MIN_US`–`DWELL_MAX_US`, in `commands.h`) | `OK dwell 400 us` |
| `B` | Blank the display | `OK blank` |
| `P` | Toggle pause: pausing blanks the display and stops scanning | `OK paused` / `OK running` |
| `Z` | Reset the telemetry counters | `OK counters cleared` |
| `M static\|pov\|sim` | Set the mode ([Architecture](architecture.md#modes)) | `OK mode pov` |
| `V <id>` | Pick a built-in volume for pov/sim (0 cube, 1 asymmetric L, 2 index bar) | `OK volume 1 …` |
| `?` | Report the current configuration | `CFG mode=… vol=… dwell=… paused=… rpm=… period=…` |
| `I` | Report firmware version and board id | `ID vmoji <version> sha=<git> board=<chip id>` |

A rejected command replies `ERR …` with the reason, for example `ERR dwell 50-5000`.
An unknown letter replies `ERR unknown`.

The **activity pixel** is the bottom-right LED (`ACTIVITY_PIXEL_ROW` and `ACTIVITY_PIXEL_COL`
in `matrix.c`). It blinks a few times after `H` or `S`, in static mode.

## Rules worth knowing

- **Display commands take over from the boot demo.** `S G X B P M V` stop the power-up
  animation, even if their arguments are rejected. `H D Z ? I` leave it running, so a
  dashboard can connect and watch.
- **Lines are short.** A line longer than the firmware's buffer (`LINE_MAX` in
  `commands.c`) is rejected with `ERR line too long`.
- **Stale input is dropped.** A partial line followed by silence (`LINE_IDLE_RESET_US`) is
  discarded, so a stray byte cannot corrupt the next command.
- **Names match exactly.** `M pov` works; `M povx` and `M simulate` are rejected.
