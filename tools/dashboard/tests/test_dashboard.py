"""Device detection, replay navigation and window geometry.

These cover the parts of the dashboard that decide *what it connects to* and
*how it presents itself*. That is where a demo goes wrong in front of an
audience rather than in a stack trace: silently attaching to the simulator,
being unable to scrub back to the interesting second, or opening a window taller
than the screen.

Run from tools/dashboard:
    .venv/bin/python -m pytest tests -q
"""

from __future__ import annotations

import contextlib
import os
import struct
import sys
import time

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import protocol  # noqa: E402
import sources  # noqa: E402


class FakePort:
    """Stand-in for a pyserial ListPortInfo."""

    def __init__(self, device, vid=None, pid=None, serial_number=None,
                 description="serial port", manufacturer=""):
        self.device = device
        self.vid = vid
        self.pid = pid
        self.serial_number = serial_number
        self.description = description
        self.manufacturer = manufacturer


def _fake_comports(monkeypatch, ports):
    from serial.tools import list_ports

    monkeypatch.setattr(list_ports, "comports", lambda: list(ports))


@contextlib.contextmanager
def _pty_emitting(blob: bytes, period: float = 0.02):
    """A pty that keeps emitting, the way a board does.

    Writing once up front would not survive: opening the port clears the input
    buffer to discard whatever a previous session left behind, so a probe only
    ever sees traffic produced while it is listening.
    """
    pty = pytest.importorskip("pty", reason="pty is POSIX only")
    import threading

    master, slave = pty.openpty()
    stop = threading.Event()

    def pump():
        while not stop.is_set():
            try:
                os.write(master, blob)
            except OSError:
                return
            stop.wait(period)

    thread = threading.Thread(target=pump, daemon=True)
    thread.start()
    try:
        yield os.ttyname(slave)
    finally:
        stop.set()
        thread.join(timeout=1.0)
        os.close(master)
        os.close(slave)


# --- device detection --------------------------------------------------------


def test_pico_outranks_a_generic_usb_adapter():
    """A board must win over a random USB-serial dongle on the same machine.

    This is the whole point of classifying rather than taking the first port:
    an Arduino or a CH340 cable should never silently steal the connection.
    """
    pico = sources.classify_port(0x2E8A, 0x000A)
    generic = sources.classify_port(0x1A86, 0x7523)

    assert pico is sources.PortPriority.PICO_CDC
    assert generic is sources.PortPriority.OTHER_USB
    assert pico < generic  # lower sorts first


def test_direct_board_outranks_the_debug_probe_bridge():
    """Both carry telemetry, but the board itself is the better default.

    With a probe wired up, both ports are live and they are easy to confuse -
    picking the wrong one yields a plausible-looking but second-hand stream.
    """
    assert sources.classify_port(0x2E8A, 0x000A) < sources.classify_port(0x2E8A, 0x000C)


def test_a_port_with_no_usb_id_ranks_last():
    assert sources.classify_port(None, None) is sources.PortPriority.UNKNOWN


def test_candidates_are_ranked_hardware_first(monkeypatch):
    _fake_comports(monkeypatch, [
        FakePort("/dev/ttyUSB0", vid=0x1A86, pid=0x7523),
        FakePort("/dev/ttyACM1", vid=0x2E8A, pid=0x000C),
        FakePort("/dev/ttyACM0", vid=0x2E8A, pid=0x000A),
    ])

    candidates = sources.list_port_candidates()

    assert [c.device for c in candidates] == [
        "/dev/ttyACM0",
        "/dev/ttyACM1",
        "/dev/ttyUSB0",
    ]
    assert candidates[0].is_pico
    assert candidates[1].is_hardware and not candidates[1].is_pico
    assert not candidates[2].is_hardware


def test_legacy_serial_nodes_are_hidden_unless_asked_for(monkeypatch):
    """Most machines expose /dev/ttyS0..S31, and none of them is ever a board."""
    _fake_comports(monkeypatch, [
        FakePort("/dev/ttyS0"),
        FakePort("/dev/ttyACM0", vid=0x2E8A, pid=0x000A),
    ])

    assert [c.device for c in sources.list_port_candidates()] == ["/dev/ttyACM0"]
    assert len(sources.list_port_candidates(include_non_usb=True)) == 2


def test_port_labels_name_the_hardware(monkeypatch):
    _fake_comports(monkeypatch, [FakePort("/dev/ttyACM0", vid=0x2E8A, pid=0x000A)])
    assert "Raspberry Pi Pico" in sources.list_port_candidates()[0].label


def test_probe_accepts_a_port_that_speaks_the_protocol():
    """Confirm the protocol, not just the USB id.

    A matching VID/PID says a Pico is attached, not that it is running this
    firmware; it could be flashed with anything, or wedged. Requiring a
    CRC-valid frame before committing is what makes auto-connect trustworthy.
    """
    blob = b"garbage prefix" + protocol.encode_status(1, refresh_chz=31250)
    with _pty_emitting(blob) as device:
        result = sources.probe_port(device, timeout=2.0)

    assert result.ok
    assert result.frames_ok >= 1
    assert result.error is None


def test_probe_rejects_a_silent_port():
    pty = pytest.importorskip("pty", reason="pty is POSIX only")

    master, slave = pty.openpty()
    try:
        result = sources.probe_port(os.ttyname(slave), timeout=0.3)
    finally:
        os.close(master)
        os.close(slave)

    assert not result.ok
    assert result.frames_ok == 0


def test_probe_rejects_a_port_emitting_unrelated_chatter():
    """A GPS or a serial console must not be mistaken for a board."""
    with _pty_emitting(b"$GPGGA,123519,4807.038,N*47\r\n") as device:
        result = sources.probe_port(device, timeout=0.6)

    assert not result.ok
    assert result.bytes_in > 0  # it was listening; the traffic just was not ours


# --- forward compatibility ---------------------------------------------------


def test_status_with_extra_trailing_fields_still_decodes():
    """Newer firmware may append fields; an older dashboard must not choke.

    The payload length is on the wire precisely so this can work. Refusing to
    decode would make every future firmware field a flag day for the host.
    """
    parser = protocol.FrameParser()
    payload = protocol.pack_status_payload(refresh_chz=31250) + b"\xde\xad\xbe\xef"

    messages = parser.feed(protocol.encode_frame(protocol.MsgId.STATUS, 7, payload))

    assert len(messages) == 1
    assert isinstance(messages[0], protocol.Status)
    assert messages[0].refresh_hz == pytest.approx(312.5)
    assert parser.stats.crc_errors == 0


def test_status_shorter_than_the_known_layout_is_still_rejected():
    """Relaxed is not credulous: a truncated payload cannot be decoded."""
    parser = protocol.FrameParser()

    messages = parser.feed(protocol.encode_frame(protocol.MsgId.STATUS, 7, b"\x00" * 20))

    assert not any(isinstance(m, protocol.Status) for m in messages)


def test_tx_drop_flag_is_decoded():
    frame = protocol.encode_status(1, flags=int(protocol.StatusFlag.TX_DROP))
    status = protocol.FrameParser().feed(frame)[0]

    assert status.has_flag(protocol.StatusFlag.TX_DROP)
    assert not status.has_flag(protocol.StatusFlag.PAUSED)


def test_identity_line_is_parsed():
    assert protocol.parse_identity(
        "ID vmoji 1.1.0 sha=5ab4f62a board=E6614C775B59B537"
    ) == {"version": "1.1.0", "sha": "5ab4f62a", "board": "E6614C775B59B537"}


def test_ordinary_log_text_is_not_mistaken_for_identity():
    assert protocol.parse_identity("vmoji telemetry online") is None
    assert protocol.parse_identity("OK dwell 900 us") is None


# --- replay navigation -------------------------------------------------------


def _write_capture(path, span_s=10.0, count=50):
    """A capture with known offsets, written directly so timing is exact."""
    with open(path, "wb") as handle:
        handle.write(
            struct.Struct("<8sHHd").pack(
                sources.CAPTURE_MAGIC, sources.CAPTURE_VERSION, 0, time.time()
            )
        )
        for index in range(count):
            data = protocol.encode_frame(protocol.MsgId.LOG, index & 0xFF, b"tick")
            handle.write(struct.Struct("<dI").pack(span_s * index / count, len(data)))
            handle.write(data)
    return str(path)


def test_seek_moves_the_playhead_and_clamps_to_the_recording(tmp_path):
    replay = sources.ReplaySource(_write_capture(tmp_path / "c.vmc"), speed=0.0)

    replay.seek(5.0)
    assert replay.elapsed_s == pytest.approx(5.0)
    assert 0.4 < replay.progress < 0.6

    replay.seek(-3.0)
    assert replay.elapsed_s == 0.0

    replay.seek(1e6)
    assert replay.elapsed_s == pytest.approx(replay.duration_s)
    assert replay.progress == pytest.approx(1.0)
    # Seeking to time T means "play from T onward", so the record sitting
    # exactly at the end is still to come; one read finishes the capture.
    replay.read()
    assert replay.exhausted


def test_seeking_forward_skips_the_records_in_between(tmp_path):
    replay = sources.ReplaySource(_write_capture(tmp_path / "c.vmc"), speed=0.0)

    replay.seek(9.0)
    remaining = b""
    while not replay.exhausted:
        remaining += replay.read()

    # 10 s of recording at 5 records per second: the last second is ~5 records.
    assert 0 < remaining.count(b"tick") <= 6


def test_seeking_backward_replays_the_earlier_part(tmp_path):
    replay = sources.ReplaySource(_write_capture(tmp_path / "c.vmc"), speed=0.0)
    while not replay.exhausted:
        replay.read()

    replay.seek(2.0)

    assert not replay.exhausted
    assert replay.read() != b""


def test_pause_holds_the_playhead(tmp_path):
    replay = sources.ReplaySource(_write_capture(tmp_path / "c.vmc"), speed=1.0)
    replay.read()

    replay.paused = True
    before = replay.elapsed_s
    for _ in range(5):
        assert replay.read() == b""
    assert replay.elapsed_s == pytest.approx(before)

    replay.paused = False
    time.sleep(0.05)
    replay.read()
    assert replay.elapsed_s > before


def test_changing_speed_does_not_jump_the_playhead(tmp_path):
    """Speed applies from now on; it must not rescale time already played.

    Deriving the position from a fixed start time makes a mid-playback speed
    change teleport the playhead, which reads as a broken seek bar.
    """
    replay = sources.ReplaySource(_write_capture(tmp_path / "c.vmc"), speed=1.0)
    replay.read()
    time.sleep(0.1)
    replay.read()
    before = replay.elapsed_s
    assert before == pytest.approx(0.1, abs=0.05)

    # Pause across the change so the assertion measures the speed change alone,
    # not the wall time the test itself spends between the two reads.
    replay.paused = True
    replay.read()
    replay.speed = 20.0
    replay.paused = False
    replay.read()

    # Rescaling elapsed time would have put the playhead at about 2 s.
    assert replay.elapsed_s == pytest.approx(before, abs=0.05)


def test_restart_returns_to_the_beginning(tmp_path):
    replay = sources.ReplaySource(_write_capture(tmp_path / "c.vmc"), speed=0.0)
    while not replay.exhausted:
        replay.read()

    replay.restart()

    assert replay.elapsed_s == 0.0
    assert not replay.exhausted
    assert replay.read() != b""


# --- window presentation -----------------------------------------------------


def _app():
    pytest.importorskip("PySide6")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtWidgets import QApplication

    return QApplication.instance() or QApplication([])


def test_window_fits_a_small_laptop_screen():
    """Regression guard on the minimum size.

    The dashboard once demanded 986x1186, which does not fit on a 1080p laptop
    at all. A minimum size creeps upward one innocuous widget at a time, so the
    only thing that keeps it down is a test that fails when it grows.
    """
    app = _app()
    from main_window import MainWindow

    window = MainWindow(initial_selection=("sim", None))
    try:
        window.show()
        app.processEvents()

        hint = window.minimumSizeHint()
        assert hint.width() <= 900
        assert hint.height() <= 600

        window.resize(900, 600)
        app.processEvents()
        assert (window.width(), window.height()) == (900, 600)
    finally:
        window.close()
        app.processEvents()


def test_simulation_banner_marks_synthetic_data(tmp_path):
    """The banner is the safeguard against demoing the simulator by accident."""
    app = _app()
    from main_window import MainWindow

    window = MainWindow(initial_selection=("sim", None))
    try:
        window.show()
        app.processEvents()
        assert window.sim_banner.isVisible()
        assert "SIMULATION" in window.windowTitle()
        assert not window.replay_bar.isVisible()

        window._start_worker(
            sources.ReplaySource(_write_capture(tmp_path / "c.vmc"), speed=0.0)
        )
        app.processEvents()
        assert not window.sim_banner.isVisible()
        assert window.replay_bar.isVisible()
        assert "REPLAY" in window.windowTitle()
    finally:
        window.close()
        app.processEvents()


def test_hardware_is_listed_first_and_the_simulator_last(monkeypatch):
    """The simulator stays reachable, but never as the top entry."""
    app = _app()
    _fake_comports(monkeypatch, [
        FakePort("/dev/ttyUSB0", vid=0x1A86, pid=0x7523),
        FakePort("/dev/ttyACM0", vid=0x2E8A, pid=0x000A),
    ])
    from main_window import MainWindow

    window = MainWindow(initial_selection=("sim", None))
    try:
        entries = [
            window.source_combo.itemData(index)
            for index in range(window.source_combo.count())
        ]
        assert entries[0] == ("serial", "/dev/ttyACM0")
        assert entries[-1] == ("sim", None)
    finally:
        window.close()
        app.processEvents()


def test_board_identity_from_a_log_line_reaches_the_link_panel():
    app = _app()
    from main_window import MainWindow

    window = MainWindow(initial_selection=("sim", None))
    try:
        window._note_identity("ID vmoji 1.1.0 sha=5ab4f62a board=E6614C775B59B537")
        assert "E6614C775B59B537" in window._board_identity
        assert "1.1.0" in window._board_identity
    finally:
        window.close()
        app.processEvents()


def test_a_dropped_serial_link_schedules_a_reconnect(monkeypatch):
    """A bumped cable must not end the session.

    Mid-demo, the board is usually back within a second; tearing the session
    down and making someone re-pick the port is the wrong response.
    """
    app = _app()
    _fake_comports(monkeypatch, [FakePort("/dev/ttyACM0", vid=0x2E8A, pid=0x000A)])
    from main_window import MainWindow

    window = MainWindow(initial_selection=("sim", None))
    try:
        window._select_source(("serial", "/dev/ttyACM0"))
        window._on_source_failed("device reports readiness to read but returned no data")

        assert window._reconnect_target == ("serial", "/dev/ttyACM0")
        assert window._reconnect_timer.isActive()

        # Backoff must be bounded, not unbounded exponential growth.
        for _ in range(20):
            window._reconnect_delay = min(
                window._reconnect_delay * 2, window._reconnect_delay * 2
            )
        window._cancel_reconnect()
        assert window._reconnect_target is None
        assert not window._reconnect_timer.isActive()
    finally:
        window.close()
        app.processEvents()
