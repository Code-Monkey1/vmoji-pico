"""Parser and model tests.

The reference vectors come from the C++ implementation:

    g++ -std=c++17 -Wall -Wextra -I vmoji tools/protocol_selftest.cpp -o /tmp/selftest
    /tmp/selftest --vectors

Pinning them here is the point. Two independent implementations of one wire
format will drift apart unless something forces them to agree, and the failure
mode of a silent drift is a dashboard that plots confident nonsense.

Run from tools/dashboard:
    .venv/bin/python -m pytest tests -q
"""

from __future__ import annotations

import pytest

import model
import protocol
import sources

# --- vectors emitted by tools/protocol_selftest.cpp --------------------------

CPP_STATUS_FRAME = bytes.fromhex(
    "aa552000010740e20100cd810100127a800c6c0c520de600ab0a0c0003000010000090010201eaf0"
)
CPP_FRAMEBUFFER_FRAME = bytes.fromhex("aa550800020881402010814020103e9c")
CPP_LOG_FRAME = bytes.fromhex(
    "aa5516000309766d6f6a692074656c656d65747279206f6e6c696e65b521"
)


def test_crc_matches_standard_check_value():
    # CRC-16/CCITT-FALSE over "123456789" is the documented 0x29B1.
    assert protocol.crc16(b"123456789") == 0x29B1


def test_status_struct_size_matches_firmware():
    assert protocol._STATUS_STRUCT.size == 32


def test_decodes_cpp_status_vector():
    parser = protocol.FrameParser(clock=lambda: 0.0)
    messages = parser.feed(CPP_STATUS_FRAME)

    assert len(messages) == 1
    status = messages[0]
    assert isinstance(status, protocol.Status)
    assert status.seq == 7
    assert status.uptime_ms == 123456
    assert status.scan_count == 98765
    assert status.refresh_chz == 31250
    assert status.refresh_hz == pytest.approx(312.5)
    assert status.period_mean_us == 3200
    assert status.period_min_us == 3180
    assert status.period_max_us == 3410
    assert status.jitter_pp_us == 230
    assert status.die_temp_c == pytest.approx(27.31)
    assert status.cmd_ok == 12
    assert status.cmd_err == 3
    assert status.rx_bytes == 4096
    assert status.row_dwell_us == 400
    assert status.glyph_id == 2
    assert status.has_flag(protocol.StatusFlag.ACTIVITY)
    assert not status.has_flag(protocol.StatusFlag.PAUSED)
    assert parser.stats.crc_errors == 0


def test_decodes_cpp_framebuffer_vector():
    parser = protocol.FrameParser(clock=lambda: 0.0)
    (message,) = parser.feed(CPP_FRAMEBUFFER_FRAME)

    assert isinstance(message, protocol.FrameBuffer)
    assert message.seq == 8
    assert message.rows == (0x81, 0x40, 0x20, 0x10, 0x81, 0x40, 0x20, 0x10)
    # 0x81 is the two outer columns of row 0.
    assert message.pixel(0, 0) and message.pixel(0, 7)
    assert not message.pixel(0, 3)


def test_decodes_cpp_log_vector():
    parser = protocol.FrameParser(clock=lambda: 0.0)
    (message,) = parser.feed(CPP_LOG_FRAME)

    assert isinstance(message, protocol.TextMessage)
    assert message.msg_id is protocol.MsgId.LOG
    assert message.text == "vmoji telemetry online"


def test_python_encoder_reproduces_cpp_bytes():
    """The strongest form of the agreement check: same inputs, same bytes."""
    payload = CPP_STATUS_FRAME[protocol.HEADER_SIZE : -protocol.CRC_SIZE]
    assert protocol.encode_frame(protocol.MsgId.STATUS, 7, payload) == CPP_STATUS_FRAME


# --- streaming behaviour ----------------------------------------------------


def test_frame_split_across_reads():
    """The realistic case: serial hands you the frame in pieces."""
    parser = protocol.FrameParser(clock=lambda: 0.0)
    for index in range(len(CPP_STATUS_FRAME) - 1):
        assert parser.feed(CPP_STATUS_FRAME[index : index + 1]) == []
    messages = parser.feed(CPP_STATUS_FRAME[-1:])
    assert len(messages) == 1


def test_multiple_frames_in_one_chunk():
    parser = protocol.FrameParser(clock=lambda: 0.0)
    messages = parser.feed(CPP_STATUS_FRAME + CPP_FRAMEBUFFER_FRAME + CPP_LOG_FRAME)
    assert [type(m).__name__ for m in messages] == ["Status", "FrameBuffer", "TextMessage"]


def test_resync_past_leading_ascii_banner():
    """The first bytes the parser ever sees are the firmware's boot banner."""
    banner = b"\r\n===== 8x8 VMOJI =====\r\n"
    parser = protocol.FrameParser(clock=lambda: 0.0)
    messages = parser.feed(banner + CPP_STATUS_FRAME)

    assert len(messages) == 1
    assert parser.stats.resync_bytes == len(banner)
    assert parser.stats.frames_ok == 1


def test_bad_crc_is_counted_and_recovered_from():
    corrupted = bytearray(CPP_STATUS_FRAME)
    corrupted[12] ^= 0xFF
    parser = protocol.FrameParser(clock=lambda: 0.0)

    messages = parser.feed(bytes(corrupted) + CPP_LOG_FRAME)

    assert parser.stats.crc_errors >= 1
    # The good frame that followed the bad one still arrives: this is the whole
    # point of resynchronising instead of flushing the buffer.
    assert any(isinstance(m, protocol.TextMessage) for m in messages)


def test_sync_word_inside_payload_does_not_derail_parser():
    payload = bytes([0, 1, 2, protocol.SYNC0, protocol.SYNC1, 5, 6, 7])
    frame = protocol.encode_frame(protocol.MsgId.LOG, 3, payload)
    parser = protocol.FrameParser(clock=lambda: 0.0)

    messages = parser.feed(frame)

    assert len(messages) == 1
    assert parser.stats.crc_errors == 0


def test_oversized_length_field_is_rejected():
    bogus = protocol.SYNC + b"\xff\xff" + b"\x01\x00" + b"\x00" * 8
    parser = protocol.FrameParser(clock=lambda: 0.0)

    parser.feed(bogus + CPP_LOG_FRAME)

    assert parser.stats.length_errors >= 1
    assert parser.stats.frames_ok == 1


def test_sequence_gap_is_detected():
    parser = protocol.FrameParser(clock=lambda: 0.0)
    parser.feed(protocol.encode_status(10))
    parser.feed(protocol.encode_status(14))

    assert parser.stats.seq_gaps == 1
    assert parser.stats.frames_dropped_estimate == 3


def test_sequence_wraps_without_false_gap():
    parser = protocol.FrameParser(clock=lambda: 0.0)
    parser.feed(protocol.encode_status(255))
    parser.feed(protocol.encode_status(0))

    assert parser.stats.seq_gaps == 0


def test_unknown_message_id_is_surfaced_not_fatal():
    parser = protocol.FrameParser(clock=lambda: 0.0)
    (message,) = parser.feed(protocol.encode_frame(0x7E, 1, b"future"))

    assert isinstance(message, protocol.UnknownMessage)
    assert message.raw_id == 0x7E
    assert parser.stats.unknown_ids == 1
    assert parser.stats.crc_errors == 0


def test_pure_noise_does_not_grow_the_buffer():
    """A tool left connected to the wrong device must not leak memory."""
    parser = protocol.FrameParser(clock=lambda: 0.0)
    for _ in range(200):
        parser.feed(bytes(range(256)))
    assert parser.pending_bytes <= protocol.MAX_FRAME


# --- model ------------------------------------------------------------------


def test_model_accumulates_series_and_derives_values():
    m = model.TelemetryModel()
    clock = iter([0.0, 0.1, 0.2])
    parser = protocol.FrameParser(clock=lambda: next(clock))

    for index, (chz, jitter) in enumerate([(30000, 100), (31000, 150), (29000, 400)]):
        m.add_messages(
            parser.feed(
                protocol.encode_status(index, refresh_chz=chz, jitter_pp_us=jitter,
                                       die_temp_c_x100=2700 + index)
            )
        )

    assert len(m.refresh_hz) == 3
    assert m.refresh_hz.latest == pytest.approx(290.0)
    assert m.jitter_pp_us.stats(seconds=10)[2] == 400
    assert m.status_count == 3
    assert m.status_rate_hz == pytest.approx(10.0, rel=0.05)


def test_series_is_bounded():
    series = model.Series("x", maxlen=10)
    for index in range(100):
        series.append(float(index), float(index))
    assert len(series) == 10
    assert series.t[0] == 90.0


def test_series_window_selects_trailing_span():
    series = model.Series("x", maxlen=1000)
    for index in range(100):
        series.append(index * 0.1, float(index))
    times, values = series.window(seconds=1.0)
    assert times[0] >= 8.8
    assert values[-1] == 99.0


# --- capture round trip -----------------------------------------------------


def test_capture_round_trip_preserves_bytes_and_order(tmp_path):
    path = tmp_path / "capture.vmc"
    writer = sources.CaptureWriter(path)
    writer.write(CPP_STATUS_FRAME)
    writer.write(CPP_LOG_FRAME)
    writer.close()

    records = sources.read_capture(path)
    assert len(records) == 2
    assert sources.concat_capture_bytes(records) == CPP_STATUS_FRAME + CPP_LOG_FRAME
    assert records[0].offset_s <= records[1].offset_s


def test_replay_feeds_the_same_parser(tmp_path):
    path = tmp_path / "capture.vmc"
    writer = sources.CaptureWriter(path)
    writer.write(CPP_STATUS_FRAME + CPP_FRAMEBUFFER_FRAME)
    writer.close()

    replay = sources.ReplaySource(path, speed=0)  # as fast as possible
    parser = protocol.FrameParser(clock=lambda: 0.0)
    messages = []
    while not replay.exhausted:
        messages.extend(parser.feed(replay.read()))

    assert [type(m).__name__ for m in messages] == ["Status", "FrameBuffer"]


def test_rejects_a_file_that_is_not_a_capture(tmp_path):
    path = tmp_path / "nope.bin"
    path.write_bytes(b"just some bytes that are not a capture header")
    with pytest.raises(sources.SourceError):
        sources.read_capture(path)


# --- simulator --------------------------------------------------------------


def test_simulator_produces_parseable_telemetry():
    sim = sources.SimSource(seed=1)
    parser = protocol.FrameParser()

    messages = []
    deadline = 60
    while deadline and not any(isinstance(m, protocol.Status) for m in messages):
        messages.extend(parser.feed(sim.read()))
        deadline -= 1

    assert any(isinstance(m, protocol.Status) for m in messages)
    assert parser.stats.crc_errors == 0


def test_simulator_honours_dwell_command_and_acks_it():
    sim = sources.SimSource(seed=2)
    parser = protocol.FrameParser()
    parser.feed(sim.read())  # clear the banner

    sim.write(protocol.cmd_dwell(1200).encode())
    acks = [m for m in parser.feed(sim.read()) if isinstance(m, protocol.TextMessage)]

    assert any("dwell 1200" in m.text for m in acks)

    # A longer dwell must show up as a slower modelled refresh rate.
    status = None
    for _ in range(80):
        for message in parser.feed(sim.read()):
            if isinstance(message, protocol.Status):
                status = message
        if status is not None:
            break
    assert status is not None
    assert status.row_dwell_us == 1200
    assert status.refresh_hz < 150


def test_simulator_rejects_a_bad_command():
    sim = sources.SimSource(seed=3)
    parser = protocol.FrameParser()
    parser.feed(sim.read())

    sim.write(b"X nonsense\n")
    acks = [m for m in parser.feed(sim.read()) if isinstance(m, protocol.TextMessage)]

    assert any("ERR" in m.text for m in acks)


def test_serial_source_over_a_pty(tmp_path):
    """Exercise SerialSource against a real serial file descriptor.

    A pty is a genuine tty, so this covers the pyserial path, the DTR/RTS
    handling and both directions of the link without needing a board plugged in.
    The bytes are written in seven-byte chunks because that is the awkward
    reality of a serial link, and it is exactly where a naive parser breaks.
    """
    pty = pytest.importorskip("pty", reason="pty is POSIX only")
    import os
    import time

    master, slave = pty.openpty()
    try:
        source = sources.SerialSource(os.ttyname(slave), 115200, timeout=0.05)
    except sources.SourceError as exc:  # pragma: no cover
        pytest.skip(f"cannot open pty as a serial port: {exc}")

    parser = protocol.FrameParser()
    blob = (
        b"=== 8x8 VMOJI ===\r\n"
        + CPP_STATUS_FRAME
        + protocol.encode_frame(protocol.MsgId.LOG, 8, b"hello from pty")
    )
    for index in range(0, len(blob), 7):
        os.write(master, blob[index : index + 7])

    messages = []
    for _ in range(60):
        messages.extend(parser.feed(source.read()))
        if len(messages) >= 2:
            break

    assert [type(m).__name__ for m in messages] == ["Status", "TextMessage"]
    assert messages[0].refresh_hz == pytest.approx(312.5)
    assert messages[1].text == "hello from pty"
    assert parser.stats.crc_errors == 0

    # And the uplink: a command must actually reach the wire.
    source.write(protocol.cmd_dwell(1234).encode())
    time.sleep(0.1)
    assert os.read(master, 64) == b"D 1234\n"

    source.close()
    os.close(master)


def test_injected_errors_are_caught_by_the_crc():
    """The simulator's error injection must exercise the real failure paths."""
    sim = sources.SimSource(error_rate=1.0, seed=4)
    parser = protocol.FrameParser()

    for _ in range(400):
        parser.feed(sim.read())

    assert parser.stats.crc_errors + parser.stats.resync_bytes > 0
