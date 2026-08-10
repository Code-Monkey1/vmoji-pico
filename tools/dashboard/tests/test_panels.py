"""The Qt-free logic pulled out of the window.

Reconnect timing, which numbers are worth highlighting, and the source
interface the reader relies on. None of this needs an event loop, which is the
point of it living outside main_window: these rules used to be reachable only by
opening a window and unplugging a board.
"""

from __future__ import annotations

import pytest

import panels
import protocol
import reconnect
import sources


def _status(**fields) -> protocol.Status:
    payload = protocol.pack_status_payload(**fields)
    return protocol.Status.unpack(payload, host_time=0.0, seq=0)


# --- reconnect policy --------------------------------------------------------


def test_backoff_doubles_but_is_bounded():
    """An unplugged board must still be noticed promptly when it comes back."""
    policy = reconnect.ReconnectPolicy()
    policy.arm(sources.SourceSelection("serial", "/dev/ttyACM0"))

    first = policy.delay_s
    assert policy.backoff() == pytest.approx(first * 2)

    for _ in range(20):
        policy.backoff()
    assert policy.delay_s == reconnect.MAX_DELAY_S


def test_rearming_the_same_target_keeps_the_accumulated_delay():
    """Otherwise every retry resets the backoff and it never backs off at all."""
    policy = reconnect.ReconnectPolicy()
    target = sources.SourceSelection("serial", "/dev/ttyACM0")
    policy.arm(target)
    policy.backoff()
    grown = policy.delay_s

    policy.arm(target)

    assert policy.delay_s == grown


def test_a_different_target_starts_the_backoff_over():
    policy = reconnect.ReconnectPolicy()
    policy.arm(sources.SourceSelection("serial", "/dev/ttyACM0"))
    policy.backoff()

    policy.arm(sources.SourceSelection("serial", "/dev/ttyACM1"))

    assert policy.delay_s == reconnect.MIN_DELAY_S


def test_the_countdown_message_names_the_device_and_the_wait():
    policy = reconnect.ReconnectPolicy()
    policy.arm(sources.SourceSelection("serial", "/dev/ttyACM0"))

    assert "/dev/ttyACM0" in policy.message(2500)
    assert "2.5 s" in policy.message(2500)
    assert "retrying now" in policy.message(0)


def test_an_unarmed_policy_reports_plain_disconnection():
    assert reconnect.ReconnectPolicy().message(1000) == "disconnected"
    assert not reconnect.ReconnectPolicy().active


# --- status panel ------------------------------------------------------------


def test_every_declared_status_key_is_rendered():
    """The key list and the renderers are one declaration; prove they agree."""
    cells = panels.status_cells(_status(), stale=False)
    assert tuple(cells) == panels.STATUS_KEYS


def test_rejected_commands_are_highlighted_only_when_there_are_some():
    assert not panels.status_cells(_status(cmd_err=0), stale=False)[
        "Commands rejected"
    ].warn
    assert panels.status_cells(_status(cmd_err=1), stale=False)[
        "Commands rejected"
    ].warn


def test_a_stale_link_casts_doubt_on_the_refresh_rate():
    """The last value stays on screen, so it has to be marked as suspect."""
    assert not panels.status_cells(_status(), stale=False)["Refresh rate"].warn
    assert panels.status_cells(_status(), stale=True)["Refresh rate"].warn


def test_flags_are_named_from_the_enum():
    flags = int(protocol.StatusFlag.PAUSED) | int(protocol.StatusFlag.TX_DROP)
    cell = panels.status_cells(_status(flags=flags), stale=False)["Flags"]

    assert "PAUSED" in cell.text
    assert "TX DROP" in cell.text
    assert cell.warn  # TX_DROP means telemetry was lost


def test_ordinary_flags_do_not_raise_an_alarm():
    """ACTIVITY and PAUSED are states, not faults."""
    cell = panels.status_cells(
        _status(flags=int(protocol.StatusFlag.PAUSED)), stale=False
    )["Flags"]

    assert cell.text == "PAUSED"
    assert not cell.warn


def test_no_flags_reads_as_a_dash():
    assert panels.status_cells(_status(), stale=False)["Flags"].text == "-"


def test_an_unknown_glyph_id_does_not_index_off_the_end():
    """A firmware with a longer glyph table must not crash the panel."""
    cell = panels.status_cells(_status(glyph_id=200), stale=False)["Glyph"]
    assert "?" in cell.text


# --- link panel --------------------------------------------------------------


def _link() -> panels.LinkState:
    return panels.LinkState(
        source_name="/dev/ttyACM0", board_identity="ABC", rate_hz=10.0, recording="-"
    )


def test_every_declared_link_key_is_rendered():
    cells = panels.link_cells(protocol.ParserStats(), _link())
    assert tuple(cells) == panels.LINK_KEYS


def test_a_healthy_link_highlights_nothing():
    cells = panels.link_cells(protocol.ParserStats(), _link())
    assert not any(cell.warn for cell in cells.values())


@pytest.mark.parametrize(
    ("field", "key"),
    [
        ("crc_errors", "CRC errors"),
        ("unknown_ids", "Unknown ids"),
        ("seq_gaps", "Sequence gaps"),
        ("frames_dropped_estimate", "Frames lost (est.)"),
    ],
)
def test_loss_counters_are_highlighted_when_non_zero(field, key):
    """These four are the ones that mean the plot is missing something."""
    cells = panels.link_cells(protocol.ParserStats(**{field: 3}), _link())
    assert cells[key].warn


# --- the source interface ----------------------------------------------------


def test_a_live_source_is_never_exhausted():
    """The reader asks every source this, so every source has to answer.

    A quiet link is not a finished one; reporting otherwise would announce
    "replay finished" on a board that simply paused.
    """
    assert not sources.SimSource().exhausted
    assert not sources.SerialSource.exhausted


def test_the_factory_builds_each_kind():
    factory = sources.SourceFactory()
    assert isinstance(factory.create(sources.SIMULATOR), sources.SimSource)


def test_the_factory_rejects_an_unknown_kind():
    with pytest.raises(sources.SourceError):
        sources.SourceFactory().create(sources.SourceSelection("carrier-pigeon", None))


def test_the_factory_rejects_a_serial_selection_with_no_port():
    with pytest.raises(sources.SourceError):
        sources.SourceFactory().create(sources.SourceSelection("serial", None))


def test_a_selection_compares_equal_to_a_plain_tuple():
    """Qt stores these as item data and compares them; tuple equality is why
    that works without teaching Qt about a custom type."""
    assert sources.SourceSelection("serial", "/dev/ttyACM0") == (
        "serial",
        "/dev/ttyACM0",
    )
    assert sources.SIMULATOR == ("sim", None)


def test_the_simulator_glyph_table_matches_the_published_names():
    """The names and the bitmaps are separate tables; they have to stay level."""
    assert len(sources.SimSource._GLYPHS) == len(protocol.GLYPH_NAMES)
