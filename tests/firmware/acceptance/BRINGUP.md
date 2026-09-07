# Manual bring-up acceptance (after flashing `vmoji.uf2`)

Drive the board over USB CDC (`/dev/ttyACM0`) or UART0. Line endings: `\n`.

## Knobs (firmware defaults)

| Knob | Default | Notes |
|------|---------|--------|
| IR GPIO | GP3 | Active-low falling edge, internal pull-up |
| IR refractory | 500 µs (`IR_REFRACTORY_US`) | Bounce shorter than this is ignored |
| Blank settle | 5 µs (`MATRIX_BLANK_SETTLE_US`) | Blank between POV mux steps |
| Sync-loss blank | 250 ms | No IR edge → display stops |

## 1. Static matrix

1. Power the Pico; open a serial terminal at 115200 (USB CDC).
2. Send `G 1` — heart glyph should appear.
3. Send `S 2 3` — score digits; activity pixel blinks.
4. Dashboard (optional): Status messages arrive; CRC errors ~0.
5. Send `P` (pause) — display freezes; board must **not** watchdog-reset.

## 2. Simulated POV (~1000 RPM)

1. Send `M sim`
2. Send `V 1` (asymmetric L)
3. Query `?` — expect `mode=sim`, `rpm` near 1000, `period` near 60000.
4. On a stationary board the matrix will flicker/glow as masks cycle; a logic
   analyzer on a column GPIO should show blank+settle then lit dwell repeating
   (~78 µs-scale steps at 1000 RPM / 768 steps).

## 3. Real IR sync (GP3)

1. Wire the IR index sensor to **GP3** (active-low / falling edge; internal pull-up).
2. Send `M pov` and `V 1`.
3. Spin the rotor (or toggle GP3 once per rev).
4. `?` should show `rpm` tracking actual speed without wild bounce from contact noise.
5. The asymmetric feature should appear locked in space, not smeared.
6. Stop the index pulses — within ~250 ms the display should blank/stop.
7. Status flag `FIFO_OVF` should stay clear under normal operation.

## 4. Regression commands

- `M static` returns to glyph mode.
- `V 0` / `V 2` switch cube / index-bar volumes in sim or pov.
- Bad input (`M nope`, `V 9`) returns `ERR …` ack.
