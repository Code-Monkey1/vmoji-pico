"""Byte sources for the dashboard, plus the capture file format.

Every source presents the same three operations - ``read``, ``write``, ``close``
- so the reader thread, the parser, and the whole GUI are identical whether the
bytes come from a USB cable, a simulator, or a file recorded last Tuesday.

That indirection is not architecture for its own sake. It buys three concrete
things:

* the application runs, and can be demonstrated, with no hardware attached;
* a field capture can be replayed through the exact production parser, so a
  decoding bug found in the lab is reproducible at a desk;
* the GUI becomes testable in CI, because a deterministic source is a fixture.

Also Qt-free on purpose. Nothing in this module imports PySide6.
"""

from __future__ import annotations

import bisect
import math
import random
import struct
import time
from dataclasses import dataclass
from enum import IntEnum
from pathlib import Path
from typing import Iterable, Protocol

import protocol

# ---------------------------------------------------------------------------
# Source interface
# ---------------------------------------------------------------------------


class SourceError(RuntimeError):
    """Raised when a source fails in a way the user needs to know about, most
    often a device that has been unplugged mid-capture."""


class Source(Protocol):
    """A bidirectional byte pipe."""

    name: str

    def read(self, max_bytes: int = 4096) -> bytes:
        """Return up to ``max_bytes``. May block briefly; must return promptly
        (empty bytes are fine) so the reader thread can observe a stop request."""

    def write(self, data: bytes) -> None:
        ...

    def close(self) -> None:
        ...

    @property
    def is_finite(self) -> bool:
        """True when the source will eventually run out, as a replay does."""


# ---------------------------------------------------------------------------
# Live serial
# ---------------------------------------------------------------------------


def list_serial_ports(usb_only: bool = True) -> list[tuple[str, str]]:
    """Available ports as (device, human description).

    Enumerating rather than hardcoding is what makes the app portable: the same
    build finds ``COM3`` on Windows and ``/dev/ttyACM0`` on Linux.

    ``usb_only`` drops ports with no USB vendor id, which on a typical Linux box
    means the 32 legacy ``/dev/ttyS*`` 8250 nodes that exist whether or not any
    hardware is behind them. Burying the one real device in that list is a small
    thing that makes a tool feel careless. Pass ``usb_only=False`` to reach a
    genuine motherboard RS-232 port.
    """
    try:
        from serial.tools import list_ports
    except ImportError:  # pragma: no cover
        return []

    everything = []
    usb = []
    for port in list_ports.comports():
        label = port.description or "serial port"
        if port.manufacturer:
            label = f"{label} ({port.manufacturer})"
        entry = (port.device, label)
        everything.append(entry)
        if port.vid is not None:
            usb.append(entry)

    return sorted(usb if usb_only else everything)


# ---------------------------------------------------------------------------
# Device detection
#
# A demo should never quietly fall back to synthetic data, so the app has to be
# able to tell a real board from any other USB serial device on the machine.
# These are the identifiers the RP2040 family actually presents.
# ---------------------------------------------------------------------------

RASPBERRY_PI_VID = 0x2E8A
PID_PICO_STDIO = 0x000A     # firmware running, telemetry on its own USB CDC
PID_BOOTSEL = 0x0003        # RP2 boot ROM: mass storage, firmware not running
PID_DEBUG_PROBE = 0x000C    # CMSIS-DAP; its second interface bridges UART0


class PortPriority(IntEnum):
    """Connection preference. Lower sorts first."""

    PICO_CDC = 0      # the board itself
    DEBUG_PROBE = 1   # the board, seen through the probe's UART bridge
    OTHER_USB = 2     # some other USB serial device; might be a board on a TTL adapter
    UNKNOWN = 3       # no USB vendor id at all, typically a legacy 8250 node


@dataclass(frozen=True)
class PortCandidate:
    device: str
    description: str
    priority: PortPriority
    vid: int | None = None
    pid: int | None = None
    serial_number: str | None = None

    @property
    def is_pico(self) -> bool:
        return self.priority is PortPriority.PICO_CDC

    @property
    def is_hardware(self) -> bool:
        """True when this is a Raspberry Pi device rather than a generic port."""
        return self.priority in (PortPriority.PICO_CDC, PortPriority.DEBUG_PROBE)

    @property
    def label(self) -> str:
        kind = {
            PortPriority.PICO_CDC: "Raspberry Pi Pico",
            PortPriority.DEBUG_PROBE: "Debug Probe (UART bridge)",
            PortPriority.OTHER_USB: self.description,
            PortPriority.UNKNOWN: self.description,
        }[self.priority]
        return f"{self.device}  -  {kind}"


def classify_port(vid: int | None, pid: int | None) -> PortPriority:
    if vid == RASPBERRY_PI_VID and pid == PID_PICO_STDIO:
        return PortPriority.PICO_CDC
    if vid == RASPBERRY_PI_VID and pid == PID_DEBUG_PROBE:
        return PortPriority.DEBUG_PROBE
    if vid is not None:
        return PortPriority.OTHER_USB
    return PortPriority.UNKNOWN


def list_port_candidates(include_non_usb: bool = False) -> list[PortCandidate]:
    """Every serial port, classified and ranked best-first.

    Ranking rather than filtering: an unrecognised adapter is still offered, it
    just sorts below a board we can positively identify.
    """
    try:
        from serial.tools import list_ports
    except ImportError:  # pragma: no cover
        return []

    candidates: list[PortCandidate] = []
    for port in list_ports.comports():
        priority = classify_port(port.vid, port.pid)
        if priority is PortPriority.UNKNOWN and not include_non_usb:
            continue
        description = port.description or "serial port"
        if port.manufacturer and port.manufacturer not in description:
            description = f"{description} ({port.manufacturer})"
        candidates.append(
            PortCandidate(
                device=port.device,
                description=description,
                priority=priority,
                vid=port.vid,
                pid=port.pid,
                serial_number=port.serial_number,
            )
        )

    candidates.sort(key=lambda c: (c.priority, c.device))
    return candidates


def detect_bootsel_boards() -> list[str]:
    """Serial numbers of boards sitting in BOOTSEL.

    A board in BOOTSEL enumerates as mass storage, so it never appears as a
    serial port. Detecting it separately turns the single most common bring-up
    mistake into a specific message instead of "no board found".

    Linux-only via sysfs, which avoids adding a USB dependency for what is a
    diagnostic nicety. Returns an empty list everywhere else.
    """
    root = Path("/sys/bus/usb/devices")
    if not root.is_dir():
        return []

    found: list[str] = []
    for entry in sorted(root.iterdir()):
        try:
            vid = (entry / "idVendor").read_text().strip()
            pid = (entry / "idProduct").read_text().strip()
        except (OSError, ValueError):
            continue
        if int(vid, 16) == RASPBERRY_PI_VID and int(pid, 16) == PID_BOOTSEL:
            try:
                serial_number = (entry / "serial").read_text().strip()
            except OSError:
                serial_number = entry.name
            found.append(serial_number)
    return found


@dataclass(frozen=True)
class ProbeResult:
    """What a short listen on a port actually produced."""

    device: str
    frames_ok: int
    bytes_in: int
    error: str | None = None

    @property
    def ok(self) -> bool:
        return self.frames_ok > 0


def probe_port(device: str, baudrate: int = 115200, timeout: float = 1.5) -> ProbeResult:
    """Listen briefly and report whether real telemetry is arriving.

    Identifying a port by its USB id says a board is plugged in, not that it is
    running our firmware. Confirming an actual decoded frame before committing
    is what stops the app from latching onto a board in a stuck state, or onto
    an unrelated adapter, and then showing an empty plot.
    """
    try:
        source = SerialSource(device, baudrate)
    except SourceError as exc:
        return ProbeResult(device, 0, 0, str(exc))

    parser = protocol.FrameParser()
    deadline = time.monotonic() + timeout
    try:
        while time.monotonic() < deadline:
            chunk = source.read(4096)
            if chunk:
                for _ in parser.feed(chunk):
                    pass
                if parser.stats.frames_ok > 0:
                    break
            else:
                time.sleep(0.005)
    except SourceError as exc:
        return ProbeResult(device, parser.stats.frames_ok, parser.stats.bytes_in, str(exc))
    finally:
        source.close()

    return ProbeResult(device, parser.stats.frames_ok, parser.stats.bytes_in)


def autodetect_port(baudrate: int = 115200, probe: bool = True,
                    timeout: float = 1.5) -> PortCandidate | None:
    """The best port that is actually streaming, or None.

    With ``probe`` disabled this returns the highest-ranked candidate without
    opening it, which is the right behaviour when the caller only wants a
    default selection rather than a guarantee.
    """
    candidates = list_port_candidates()
    if not candidates:
        return None
    if not probe:
        return candidates[0]

    for candidate in candidates:
        if probe_port(candidate.device, baudrate, timeout).ok:
            return candidate
    return None


class SerialSource:
    """A live USB CDC or UART link, via pyserial."""

    is_finite = False

    def __init__(self, port: str, baudrate: int = 115200, timeout: float = 0.05) -> None:
        try:
            import serial
        except ImportError as exc:  # pragma: no cover
            raise SourceError("pyserial is not installed") from exc

        self.name = f"{port} @ {baudrate}"
        self._port_name = port
        try:
            self._serial = serial.Serial(port=port, baudrate=baudrate, timeout=timeout)
        except Exception as exc:
            raise SourceError(f"could not open {port}: {exc}") from exc

        # DTR must stay asserted: pico_stdio_usb gates all CDC output on
        # tud_cdc_connected(), which tracks DTR, so a deasserted line makes the
        # firmware discard every telemetry frame while UART0 keeps working.
        try:
            self._serial.dtr = True
            self._serial.rts = True
        except (OSError, ValueError):
            pass
        # Let the firmware observe the line change before discarding whatever
        # the previous session left in the kernel buffer.
        time.sleep(0.2)
        try:
            self._serial.reset_input_buffer()
        except (OSError, ValueError):
            pass

    def read(self, max_bytes: int = 4096) -> bytes:
        try:
            waiting = self._serial.in_waiting
            # Read at least one byte so the configured timeout paces the loop
            # instead of spinning the CPU at 100%.
            return self._serial.read(max(1, min(waiting, max_bytes)))
        except Exception as exc:
            raise SourceError(f"{self._port_name} read failed: {exc}") from exc

    def write(self, data: bytes) -> None:
        try:
            self._serial.write(data)
            self._serial.flush()
        except Exception as exc:
            raise SourceError(f"{self._port_name} write failed: {exc}") from exc

    def close(self) -> None:
        try:
            self._serial.close()
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Simulator
# ---------------------------------------------------------------------------


class SimSource:
    """Synthetic telemetry that behaves like the firmware.

    It models the scan loop rather than emitting random numbers: the row dwell
    time determines the scan period, so raising the dwell from the control panel
    visibly lowers the refresh rate on the plot, exactly as it does on hardware.
    Jitter is drawn from a narrow distribution with occasional outliers, because
    that is the shape real scan-loop jitter has - mostly tight, with spikes when
    something else steals time.

    ``error_rate`` injects deliberate corruption so the CRC and resync counters
    can be demonstrated on demand. Being able to *show* that the parser rejects
    bad frames is more convincing than asserting that it does.
    """

    is_finite = False
    SETTLE_US = 5
    ROWS = 8
    LOOP_OVERHEAD_US = 40

    def __init__(self, error_rate: float = 0.0, seed: int | None = None) -> None:
        self.name = "simulator"
        self._rng = random.Random(seed)
        self._error_rate = error_rate
        self._seq = 0
        self._pending = bytearray()
        self._start = time.monotonic()
        self._next_status = self._start + 0.1
        self._last_status = self._start
        self._next_framebuffer = self._start
        self._scan_count = 0
        self._scan_debt = 0.0
        self._cmd_ok = 0
        self._cmd_err = 0
        self._rx_bytes = 0
        self._row_dwell_us = 400
        self._glyph_id = 1
        self._flags = 0
        self._paused = False
        self._rows = self._glyph_rows(self._glyph_id)

        banner = (
            b"\r\n=====================================\r\n"
            b"=========     8x8 VMOJI     =========\r\n"
            b"===  binary telemetry @ 10 Hz     ===\r\n"
            b"=====================================\r\n"
        )
        self._pending.extend(banner)
        self._emit(protocol.MsgId.LOG, b"vmoji telemetry online (simulated)")

    # -- glyphs, mirroring the firmware table ------------------------------

    _GLYPHS: tuple[tuple[int, ...], ...] = (
        (0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00),
        (0x66, 0x99, 0x99, 0x89, 0x81, 0x42, 0x24, 0x18),
        (0xFC, 0xCC, 0xCC, 0xFC, 0xC0, 0xC0, 0xC0, 0xC0),
        (0xFC, 0xCC, 0xCC, 0xFC, 0xD0, 0xC8, 0xC4, 0xC2),
        (0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55),
        (0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF),
    )

    def _glyph_rows(self, glyph_id: int) -> tuple[int, ...]:
        if 0 <= glyph_id < len(self._GLYPHS):
            return self._GLYPHS[glyph_id]
        return self._GLYPHS[0]

    # -- framing helpers ---------------------------------------------------

    def _emit(self, msg_id: int, payload: bytes) -> None:
        frame = protocol.encode_frame(msg_id, self._seq, payload)
        self._seq = (self._seq + 1) & 0xFF

        if self._error_rate > 0 and self._rng.random() < self._error_rate:
            mutable = bytearray(frame)
            choice = self._rng.random()
            if choice < 0.5 and len(mutable) > protocol.HEADER_SIZE:
                # Flip a payload bit: framing is intact, the CRC must catch it.
                index = self._rng.randrange(protocol.HEADER_SIZE, len(mutable))
                mutable[index] ^= 1 << self._rng.randrange(8)
                frame = bytes(mutable)
            elif choice < 0.8:
                # Truncate: the parser must wait rather than misdecode.
                frame = bytes(mutable[: max(3, len(mutable) // 2)])
            else:
                # Line noise between frames: must be counted as resync bytes.
                frame = bytes(self._rng.randrange(256) for _ in range(6)) + bytes(mutable)

        self._pending.extend(frame)

    # -- the modelled scan loop -------------------------------------------

    def _nominal_period_us(self) -> float:
        return self.ROWS * (self._row_dwell_us + self.SETTLE_US) + self.LOOP_OVERHEAD_US

    def _sample_period_us(self) -> int:
        nominal = self._nominal_period_us()
        value = self._rng.gauss(nominal, nominal * 0.004)
        if self._rng.random() < 0.02:
            # An occasional spike, as if the loop lost time to command handling.
            value += nominal * self._rng.uniform(0.05, 0.30)
        return max(1, min(0xFFFF, int(value)))

    def _build_status(self, elapsed_us: float) -> bytes:
        # Carry the fractional remainder across intervals. Without it, rounding
        # the scan count down every time produces a sawtooth in the derived rate
        # that looks like a real instability and is not one.
        exact = elapsed_us / self._nominal_period_us() + self._scan_debt
        scans = max(1, int(exact))
        self._scan_debt = exact - scans

        samples = [self._sample_period_us() for _ in range(scans)]
        self._scan_count += scans
        mean = int(sum(samples) / len(samples))
        low = min(samples)
        high = max(samples)
        # Rate from the measured mean period, which is what makes it the inverse
        # of the period plot rather than an independently noisy quantity.
        refresh_chz = min(0xFFFF, int(100_000_000 / max(1, mean)))

        # A slow thermal drift so the temperature plot is not a flat line.
        uptime_s = time.monotonic() - self._start
        temp_c = 26.5 + 2.2 * (1.0 - math.exp(-uptime_s / 90.0)) + self._rng.gauss(0, 0.05)

        return protocol.pack_status_payload(
            uptime_ms=int(uptime_s * 1000),
            scan_count=self._scan_count,
            refresh_chz=refresh_chz,
            period_mean_us=mean,
            period_min_us=low,
            period_max_us=high,
            jitter_pp_us=high - low,
            die_temp_c_x100=int(temp_c * 100),
            cmd_ok=self._cmd_ok,
            cmd_err=self._cmd_err,
            rx_bytes=self._rx_bytes,
            row_dwell_us=self._row_dwell_us,
            glyph_id=self._glyph_id,
            flags=self._flags,
        )

    def _service(self) -> None:
        now = time.monotonic()
        if now >= self._next_status:
            elapsed_us = max(1.0, (now - self._last_status) * 1_000_000)
            self._last_status = now
            if not self._paused:
                self._emit(protocol.MsgId.STATUS, self._build_status(elapsed_us))
            # Advance on a fixed schedule rather than from `now`, so the emitted
            # rate is genuinely 10 Hz instead of drifting slower by however long
            # each service call took.
            self._next_status += 0.1
            if self._next_status < now:
                self._next_status = now + 0.1
        if now >= self._next_framebuffer:
            self._emit(protocol.MsgId.FRAMEBUFFER, bytes(self._rows))
            self._next_framebuffer += 0.5
            if self._next_framebuffer < now:
                self._next_framebuffer = now + 0.5

    # -- Source interface --------------------------------------------------

    def read(self, max_bytes: int = 4096) -> bytes:
        self._service()
        if not self._pending:
            time.sleep(0.01)
            return b""
        take = min(max_bytes, len(self._pending))
        chunk = bytes(self._pending[:take])
        del self._pending[:take]
        return chunk

    def write(self, data: bytes) -> None:
        """Interpret host commands the way the firmware does."""
        self._rx_bytes += len(data)
        for raw_line in data.decode("ascii", errors="replace").splitlines():
            line = raw_line.strip()
            if not line:
                continue
            verb, _, argument = line.partition(" ")
            argument = argument.strip()
            ok = True
            ack = ""

            if verb == "G" and argument.isdigit() and int(argument) < len(self._GLYPHS):
                self._glyph_id = int(argument)
                self._rows = self._glyph_rows(self._glyph_id)
                ack = f"OK glyph {self._glyph_id}"
            elif verb == "D" and argument.isdigit() and 50 <= int(argument) <= 5000:
                self._row_dwell_us = int(argument)
                ack = f"OK dwell {self._row_dwell_us} us"
            elif verb == "B":
                self._glyph_id = 0
                self._rows = self._glyph_rows(0)
                ack = "OK blank"
            elif verb == "P":
                self._paused = not self._paused
                self._flags ^= int(protocol.StatusFlag.PAUSED)
                ack = "OK paused" if self._paused else "OK running"
            elif verb == "Z":
                self._scan_count = 0
                self._scan_debt = 0.0
                self._cmd_ok = 0
                self._cmd_err = 0
                self._rx_bytes = 0
                ack = "OK counters cleared"
            elif verb == "H":
                ack = "OK heartbeat"
            elif verb == "?":
                ack = f"CFG dwell={self._row_dwell_us} paused={int(self._paused)}"
            elif verb == "S":
                parts = argument.split()
                if len(parts) == 2 and all(p.isdigit() for p in parts):
                    self._glyph_id = 0
                    ack = f"OK {parts[0]}-{parts[1]}"
                else:
                    ok = False
                    ack = "ERR score"
            else:
                ok = False
                ack = "ERR unknown"

            if ok:
                self._cmd_ok += 1
            else:
                self._cmd_err += 1
            self._emit(protocol.MsgId.ACK, ack.encode("ascii"))

    def close(self) -> None:
        self._pending.clear()


# ---------------------------------------------------------------------------
# Capture files
# ---------------------------------------------------------------------------

CAPTURE_MAGIC = b"VMOJICAP"
CAPTURE_VERSION = 1
_CAPTURE_HEADER = struct.Struct("<8sHHd")
_RECORD_HEADER = struct.Struct("<dI")


@dataclass(frozen=True)
class CaptureRecord:
    offset_s: float
    data: bytes


class CaptureWriter:
    """Appends the raw byte stream with host timestamps.

    Logging the *undecoded* bytes rather than decoded records is a deliberate
    choice. A decoded log can only ever be as correct as the parser that wrote
    it; a raw capture lets you fix the parser afterwards and re-run history. It
    also preserves the CRC failures and the line noise, which are usually the
    interesting part of a bad field test.
    """

    def __init__(self, path: str | Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._file = self.path.open("wb")
        self._start = time.monotonic()
        self._file.write(
            _CAPTURE_HEADER.pack(CAPTURE_MAGIC, CAPTURE_VERSION, 0, time.time())
        )
        self._file.flush()
        self.bytes_written = 0
        self.records_written = 0

    def write(self, data: bytes) -> None:
        if not data:
            return
        offset = time.monotonic() - self._start
        self._file.write(_RECORD_HEADER.pack(offset, len(data)))
        self._file.write(data)
        self.bytes_written += len(data)
        self.records_written += 1

    @property
    def duration_s(self) -> float:
        return time.monotonic() - self._start

    def close(self) -> None:
        try:
            self._file.flush()
            self._file.close()
        except Exception:
            pass


def read_capture(path: str | Path) -> list[CaptureRecord]:
    raw = Path(path).read_bytes()
    if len(raw) < _CAPTURE_HEADER.size:
        raise SourceError("capture file is truncated")
    magic, version, _reserved, _wall = _CAPTURE_HEADER.unpack_from(raw, 0)
    if magic != CAPTURE_MAGIC:
        raise SourceError("not a vmoji capture file")
    if version != CAPTURE_VERSION:
        raise SourceError(f"unsupported capture version {version}")

    records: list[CaptureRecord] = []
    cursor = _CAPTURE_HEADER.size
    while cursor + _RECORD_HEADER.size <= len(raw):
        offset, length = _RECORD_HEADER.unpack_from(raw, cursor)
        cursor += _RECORD_HEADER.size
        if cursor + length > len(raw):
            # A capture cut short by a crash or a yanked cable is normal; keep
            # what was recorded rather than refusing to open the file.
            break
        records.append(CaptureRecord(offset, raw[cursor : cursor + length]))
        cursor += length
    return records


class ReplaySource:
    """Replays a capture through the production parser.

    ``speed`` of 1.0 honours the recorded inter-arrival times, which matters when
    you are trying to reproduce a timing-dependent problem. Higher multiples, and
    ``speed=0`` for as-fast-as-possible, are for scrubbing through a long capture
    to find the interesting minute.
    """

    is_finite = True

    def __init__(self, path: str | Path, speed: float = 1.0, loop: bool = False) -> None:
        self._records = read_capture(path)
        if not self._records:
            raise SourceError("capture file contains no data")
        self.name = f"replay {Path(path).name}"
        self.speed = speed
        self.loop = loop
        self.paused = False
        self._offsets = [record.offset_s for record in self._records]
        self._index = 0
        # Position is integrated from wall-clock deltas rather than derived from
        # a fixed start time. That is what lets pause hold and a speed change
        # take effect from here on, instead of retroactively rescaling the time
        # already played and jumping the playhead.
        self._position_s = 0.0
        self._last_tick = time.monotonic()

    @property
    def duration_s(self) -> float:
        return self._records[-1].offset_s if self._records else 0.0

    @property
    def elapsed_s(self) -> float:
        return min(self._position_s, self.duration_s)

    @property
    def progress(self) -> float:
        duration = self.duration_s
        return min(1.0, self._position_s / duration) if duration > 0 else 1.0

    @property
    def exhausted(self) -> bool:
        return self._index >= len(self._records)

    def restart(self) -> None:
        self.seek(0.0)

    def seek(self, offset_s: float) -> None:
        """Jump to a point in recorded time.

        The byte stream is cut mid-frame, so the parser will resynchronise at
        the new position and count the partial frame as resync bytes. That is
        the honest outcome of seeking a byte stream, and exactly the recovery
        path the parser exists to provide.
        """
        offset = max(0.0, min(offset_s, self.duration_s))
        self._position_s = offset
        self._last_tick = time.monotonic()
        self._index = bisect.bisect_left(self._offsets, offset)

    def _advance(self) -> float:
        now = time.monotonic()
        delta = now - self._last_tick
        self._last_tick = now
        if not self.paused:
            self._position_s += delta * self.speed
        return self._position_s

    def read(self, max_bytes: int = 4096) -> bytes:
        if self.paused:
            # Stamp the clock after the sleep, not before: time spent parked
            # must not be charged to the playhead when playback resumes.
            time.sleep(0.005)
            self._last_tick = time.monotonic()
            return b""

        if self.exhausted:
            if not self.loop:
                return b""
            self.restart()

        if self.speed <= 0:  # as fast as possible
            record = self._records[self._index]
            self._index += 1
            self._position_s = record.offset_s
            return record.data

        elapsed = self._advance()
        out = bytearray()
        while self._index < len(self._records):
            record = self._records[self._index]
            if record.offset_s > elapsed:
                break
            out.extend(record.data)
            self._index += 1
            if len(out) >= max_bytes:
                break
        if not out:
            time.sleep(0.005)
        return bytes(out)

    def write(self, data: bytes) -> None:
        """Commands are accepted and discarded: a recording cannot be steered.

        Silently ignoring is right here - the alternative is disabling the whole
        control panel during replay, which makes the mode feel broken.
        """

    def close(self) -> None:
        self._records = []


def concat_capture_bytes(records: Iterable[CaptureRecord]) -> bytes:
    """The whole capture as one blob, for offline parsing and tests."""
    return b"".join(record.data for record in records)
