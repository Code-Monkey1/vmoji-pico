# vmoji telemetry dashboard

A real-time instrumentation dashboard for the vmoji volumetric display, built to
debug the RP2040 firmware's scan loop from a PC over USB or UART.

![The dashboard streaming from the simulator](docs/dashboard.png)

The screenshot shows a live session. The two steps in the refresh-rate trace are
row-dwell changes sent from the control panel: raising the dwell from 400 us to
700 us drops the scan rate from ~400 Hz to ~190 Hz, and the scan-period trace
moves inversely. That correlation is the entire point of the tool - it turns "the
display looks dim" into a number you can act on.

## Why this exists

The display is a real-time system. An 8x8 matrix multiplexed one row at a time
only looks like an image because the scan loop is fast and *regular*; if the loop
loses time to command handling or a slow serial write, the result is visible
flicker and uneven brightness. None of that is diagnosable from the firmware
side, because the act of printing debug output is itself the thing that perturbs
the timing.

So the firmware measures its own scan interval, accumulates min/mean/max over a
100 ms window, and ships that as a compact binary frame. The host does the
plotting, the storage and the interpretation.

## Architecture

```
 ┌─────────────┐
 │ SerialSource│──┐
 │ SimSource   │──┼──▶ ReaderWorker ──queued signal──▶ TelemetryModel
 │ ReplaySource│──┘   (on a QThread)                  (bounded deques)
 └─────────────┘            │                               │
                            ▼                    QTimer @ 30 Hz
                      CaptureWriter                         │
                       (.vmc file) ─────────────────────▶  views
                                    replay
```

Four decisions carry the design:

**The reader thread never touches a widget.** `ReaderWorker` is a plain `QObject`
moved onto a `QThread`. It owns the source and the parser, and it communicates
only by emitting signals. Because the connections are made from the GUI thread,
Qt delivers them as queued connections and marshals the payload onto the event
loop. Blocking reads stay off the event loop, so the UI never freezes, and there
is not a single explicit lock in the GUI path.

**The data rate and the frame rate are independent.** Messages are appended to
the model on arrival; a `QTimer` repaints at 30 Hz regardless. Nobody can see
faster than that, and coupling repaints to arrivals is the standard way these
tools fall over when the data rate rises. The same UI would work unchanged at
10 kHz.

**Every buffer is bounded.** Series are `deque(maxlen=12000)` - 20 minutes at
10 Hz - and the log view is capped at 2000 blocks. A monitoring tool gets left
running for days, and an unbounded list is a memory leak with a good excuse.
pyqtgraph is configured with `setDownsampling(auto=True, mode='peak')` and
`setClipToView(True)`, so only the visible, decimated samples are rasterised.

**The source is swappable.** The app runs identically off a live board, a
simulator, or a recorded capture. That means it can be developed and demonstrated
with no hardware, and it means a field capture can be re-run through the exact
production parser.

## The wire protocol

Defined once, in [`../../blink/telemetry_frame.h`](../../blink/telemetry_frame.h),
and shaped after GNSS receiver binary protocols such as u-blox UBX and RTCM 3.x:

```
offset  size  field
0       2     sync word 0xAA 0x55
2       2     payload length, u16 little-endian
4       1     message id
5       1     sequence number (wraps at 256)
6       N     payload
6+N     2     CRC-16/CCITT-FALSE over offsets [2, 6+N)
```

Each element earns its place:

- **Sync word** so a listener can lock onto a stream it joined mid-frame.
- **Explicit length** so the reader knows where the message ends without escaping
  or delimiters, which is what lets the payload contain arbitrary bytes.
- **Sequence number** so the host can *detect loss it cannot prevent*. A gap is
  reported rather than silently interpolated.
- **CRC** so corrupted frames are dropped instead of plotted. It covers the length
  and id but not the sync word, so a sync word occurring inside payload data
  cannot produce a frame that also passes the CRC.

Messages: `Status` (0x01, 32-byte payload at 10 Hz), `FrameBuffer` (0x02, the 8x8
bitmap at 2 Hz), `Log` (0x03) and `Ack` (0x10), both ASCII.

`Status` carries uptime, total scan count, measured refresh rate in centi-hertz,
scan period min/mean/max, peak-to-peak jitter, RP2040 die temperature from the
on-chip sensor, accepted and rejected command counts, received byte count,
current row dwell, glyph id and status flags.

The flags are `ACTIVITY` (0x01, the activity pixel is lit), `OVERRUN` (0x02, the
UART receive ring dropped a byte), `PAUSED` (0x04, scanning suspended by
command) and `TX_DROP` (0x08, a telemetry frame was discarded because a link
could not keep up). `TX_DROP` reports a full transmit ring on the UART, or on
USB while a host is attached; bytes produced with no USB host attached are
discarded without raising it, so the flag stays meaningful on a UART-only
setup. A host that is attached but not draining its endpoint is the one gap:
the write gives up after `PICO_STDIO_USB_STDOUT_TIMEOUT_US` and the loss shows
as a gap in sequence numbers rather than as this flag.

A host that receives a `Status` payload *longer* than the 32
bytes it knows about decodes the prefix and ignores the rest, so newer firmware
can add fields without breaking an older dashboard.

### Why the uplink is ASCII

Commands stay line-oriented text (`S 2 3`, `G 4`, `D 900`, `B`, `P`, `Z`, `?`, `I`) so
the board can still be driven from `minicom` with no tooling at all during
bring-up. Framing and a CRC earn their keep on a 10 Hz downlink carrying packed
binary; they are pure overhead on six commands a minute typed by a human.

### Keeping two implementations honest

The protocol has a C++ implementation (firmware and host) and a Python one
(dashboard). Two implementations of one wire format drift apart unless something
forces them to agree, and a silent drift shows up weeks later as "the dashboard
is wrong."

So [`../protocol_selftest.cpp`](../protocol_selftest.cpp) emits reference vectors,
and `tests/test_protocol.py` pins them:

```bash
# From the repo root: the C++ side, including its own checks
g++ -std=c++17 -Wall -Wextra -I blink tools/protocol_selftest.cpp -o /tmp/selftest
/tmp/selftest
/tmp/selftest --vectors        # hex vectors consumed by the Python tests
```

The strongest of those tests asserts the Python encoder reproduces the C++ bytes
exactly.

## Running it

```bash
cd tools/dashboard
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

.venv/bin/python app.py                       # find a board; simulator only if none
.venv/bin/python app.py --sim                 # force the simulator
.venv/bin/python app.py --list-ports          # enumerate and rank serial ports
.venv/bin/python app.py --port /dev/ttyACM0   # a specific port, no searching
.venv/bin/python app.py --no-probe            # skip the confirm-a-frame check
.venv/bin/python app.py --replay session.vmc  # replay a capture
.venv/bin/python app.py --record out.vmc      # record from the start, no dialog
.venv/bin/python app.py --error-rate 0.05     # corrupt 5% of frames on purpose
```

### Finding the board

With no arguments the dashboard looks for real hardware and only falls back to
the simulator if there is none. Ports are ranked by USB id - the Pico's own CDC
interface (`2e8a:000a`) first, then a Debug Probe's UART bridge (`2e8a:000c`),
then anything else - and the chosen port must produce one CRC-valid frame before
the dashboard commits to it. A matching USB id only proves a Pico is plugged in,
not that it is running this firmware, so the frame is the part that counts.

The simulator is deliberately convincing, which makes it dangerous in front of an
audience. It is therefore always last in the source list, never auto-selected,
and while it is running the window wears a **SIMULATION** banner and a title-bar
marker. When a real board is connected the Link panel shows its unique chip id,
so "is this actually the hardware?" has a visible answer at all times.

If a live link drops - a bumped USB cable is the usual cause - the dashboard
reconnects on its own with a bounded backoff rather than ending the session, and
it re-scans for ports every two seconds so a board plugged in later shows up
without pressing Rescan.

### Replaying a capture

A recording is the one source you can actually navigate, so it gets a transport
bar: play/pause, restart, loop, a seek slider with elapsed and total time, and a
speed control. Seeking cuts the byte stream mid-frame and the parser
resynchronises at the new position, which is the honest outcome of seeking a
byte stream and the same recovery path a noisy link exercises.

On Linux, PySide6 6.5+ needs `libxcb-cursor0` for the xcb platform plugin:

```bash
sudo apt install libxcb-cursor0
```

### Flashing the firmware

```bash
cd blink
export PICO_SDK_PATH=$HOME/.pico-sdk/sdk/2.3.0
export PATH="$HOME/.pico-sdk/toolchain/14_2_Rel1/bin:$PATH"
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
ninja -C build
# then copy build/blink.uf2 onto the board in BOOTSEL mode, or flash over SWD
```

The firmware sends telemetry on **both** USB CDC (`/dev/ttyACM0`) and UART0
(GP0 TX / GP1 RX at 115200 8N1), so either transport works.

On UART the very first bytes are an unframed ASCII banner, which doubles as a
permanent test that the parser can find its sync word in a stream that does not
start with one. USB behaves differently and it is worth knowing why: the CDC
stack discards everything written before a host opens the port, so a dashboard
attaching later never sees the banner and starts mid-stream instead. Board
identity therefore travels as a framed `Log` message rather than as banner text:

```
ID vmoji 1.1.0 sha=5ab4f62a board=E6614C775B59B537
```

The firmware repeats it every 10 s and on demand via the `I` command, so it
reaches a host regardless of when that host arrived. `board=` is the RP2040's
unique chip id, which is what lets the dashboard name the specific board on
screen - and what makes a live demo distinguishable from the simulator.

### Bring-up check

Run this before opening the GUI. If something is wrong - wrong port, wrong baud,
firmware not running, TX and RX swapped - it says so in one line, instead of
leaving you staring at an empty plot unsure whether the fault is in the firmware
or the dashboard:

```bash
.venv/bin/python verify_link.py --port /dev/ttyACM0
.venv/bin/python verify_link.py --port /dev/ttyACM0 --command "D 900"
.venv/bin/python verify_link.py                       # sanity-check the simulator
```

It checks the numbers, not just that bytes moved: telemetry arriving well under
10 Hz, a zero refresh rate, an implausible die temperature, a CRC error rate over
1%, or jitter exceeding the mean scan period each produce a specific warning. It
exits non-zero on failure, so it works in a script.

### Tests

```bash
cd tools/dashboard
.venv/bin/python -m pytest tests -q
```

61 tests, no hardware required.

The protocol tests cover the cross-language vectors, frames split byte-by-byte
across reads, resynchronisation past a boot banner, CRC rejection and recovery,
oversized length fields, sequence gaps and 8-bit wrap, unknown message ids, a
sync word embedded in a payload, buffer growth under pure noise, capture
round-tripping, and `SerialSource` driven over a pty so the real pyserial path is
exercised in both directions without a board attached.

The dashboard tests cover port ranking and the probe - including a pty that
emits unrelated chatter, which must *not* be mistaken for a board - replay
seeking, pausing and speed changes, a `Status` payload carrying extra trailing
fields from hypothetical newer firmware, and the window's minimum size. That last
one is a regression guard with a specific history: the minimum had reached
986x1186, which does not fit on a 1080p laptop. A minimum size grows one
innocuous widget at a time, so the only thing that keeps it down is a test that
fails when it grows.

## Repository layout

| Path | Role |
|---|---|
| `blink/telemetry_frame.h` | C++17 framing, `constexpr` CRC table, packed payloads. Compiles for both the Pico and the host |
| `blink/telemetry_flags.h` | Status flag bits, plain C, the single definition all three languages read |
| `blink/telemetry.h` | `extern "C"` interface so `blink.c` can call the C++ emitter |
| `blink/telemetry.cpp` | The emitter: per-scan statistics, die temperature, frame output |
| `blink/blink.c` | Matrix scan loop, IRQ-driven UART ring buffer, command handling |
| `tools/protocol_selftest.cpp` | Host self-test and reference vector generator |
| `tools/dashboard/protocol.py` | Parser, messages, statistics. Qt-free |
| `tools/dashboard/sources.py` | Serial, simulator, replay sources; capture format. Qt-free |
| `tools/dashboard/model.py` | Bounded time series. Qt-free |
| `tools/dashboard/reader.py` | `QThread` worker |
| `tools/dashboard/widgets.py` | LED matrix view, key/value panel |
| `tools/dashboard/main_window.py` | Layout, wiring, repaint loop |
| `tools/dashboard/app.py` | CLI entry point |

The Qt-free boundary is deliberate: the parser, the sources and the model are
plain Python and testable with plain pytest, and the Qt layer on top is thin.

## Things worth knowing

- **The firmware measures, the host interprets.** The device reports its observed
  scan interval, not a nominal figure from a datasheet. When the two disagree,
  the observation is what matters.
- **The observed telemetry rate is displayed alongside the firmware's reported
  refresh rate.** Two independent numbers, useful precisely when they disagree,
  because that is how you tell a firmware stall from a link problem.
- **Error counters are always visible** and highlight when non-zero. A debug tool
  that cannot tell you the link is degrading is worse than no tool, because it
  invites you to trust the plot.
- **Captures store raw bytes, not decoded records.** A decoded log can only ever
  be as correct as the parser that wrote it. Raw bytes plus host timestamps mean
  you can fix the parser and re-run history - and the CRC failures and line noise
  are preserved, which is usually the interesting part of a bad field test.
- **`--error-rate` is a feature, not a debug leftover.** Being able to *show* that
  the parser rejects corrupted frames and resynchronises is more convincing than
  asserting it.
- **Measuring timing with a blocking write changes what you measure.** The
  emitter originally pushed each frame out with `putchar_raw` per byte plus a
  blocking `uart_write_blocking`, which stalled the scan loop for longer than a
  row dwell every reporting interval. The instrument was the largest source of
  the jitter it was reporting:

  | | peak-to-peak jitter | worst scan period |
  |---|---|---|
  | blocking write | 1444 us | 4700 us |
  | queued, drained by IRQ | 57 us | 3317 us |

  Frames now go into per-link ring buffers. UART0 drains under its transmit
  interrupt; USB drains in bounded batches from the main loop, as one
  `stdio_put_string` call for the whole chunk rather than one stdio round trip
  per byte. A frame that will not fit is dropped whole rather than truncated -
  half a frame just costs the host a resync - and the drop raises a `TX DROP`
  status flag, so the gap is visible instead of silent.

## Possible next steps

- TCP source, so a board on a bench elsewhere can be monitored over the network
  (the `Source` protocol already accommodates it).
- A correlation view: dwell setting against achieved rate and jitter.
- CSV/Parquet export of the decoded series for offline analysis.
- PyInstaller packaging with a GitHub Actions matrix over Windows and Linux.
- Move the parser hot loop into C++ via pybind11 if the frame rate ever justifies
  it, reusing `telemetry_frame.h` so there is still one definition of the format.
