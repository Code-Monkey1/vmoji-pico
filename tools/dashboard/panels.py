"""What the two readout panels say, and when a value should raise an eyebrow.

Each row is declared once, as a key next to the function that renders it. The
key order *is* the display order, so the panel's layout, its formatting and its
warning conditions cannot drift apart - previously the keys were listed in one
place, formatted in a second, and re-formatted with a warn flag in a third.

Qt-free, so the rules about which numbers matter are testable without a window.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

import protocol


@dataclass(frozen=True)
class Cell:
    """One rendered value, and whether it should be highlighted."""

    text: str
    warn: bool = False


@dataclass(frozen=True)
class LinkState:
    """Everything the link panel shows that is not parser statistics."""

    source_name: str
    board_identity: str
    rate_hz: float
    recording: str


def _keys(specs: tuple[tuple[str, Callable], ...]) -> tuple[str, ...]:
    return tuple(key for key, _ in specs)


# --- receiver status ---------------------------------------------------------
#
# `stale` is threaded through so the refresh rate can be marked suspect when
# telemetry has stopped: the last value stays on screen and would otherwise look
# current.

STATUS_SPECS: tuple[tuple[str, Callable[[protocol.Status, bool], Cell]], ...] = (
    ("Uptime", lambda s, stale: Cell(f"{s.uptime_s:,.1f} s")),
    ("Refresh rate", lambda s, stale: Cell(f"{s.refresh_hz:,.2f} Hz", warn=stale)),
    ("Scan period (mean)", lambda s, stale: Cell(f"{s.period_mean_us:,} us")),
    ("Scan period (min)", lambda s, stale: Cell(f"{s.period_min_us:,} us")),
    ("Scan period (max)", lambda s, stale: Cell(f"{s.period_max_us:,} us")),
    ("Jitter (pk-pk)", lambda s, stale: Cell(f"{s.jitter_pp_us:,} us")),
    ("Die temperature", lambda s, stale: Cell(f"{s.die_temp_c:.2f} C")),
    ("Row dwell", lambda s, stale: Cell(f"{s.row_dwell_us:,} us")),
    ("Scans", lambda s, stale: Cell(f"{s.scan_count:,}")),
    (
        "Glyph",
        lambda s, stale: Cell(f"{s.glyph_id}  {protocol.glyph_name(s.glyph_id)}"),
    ),
    ("Commands OK", lambda s, stale: Cell(f"{s.cmd_ok:,}")),
    (
        "Commands rejected",
        lambda s, stale: Cell(f"{s.cmd_err:,}", warn=s.cmd_err > 0),
    ),
    ("Flags", lambda s, stale: _flags_cell(s)),
)

STATUS_KEYS = _keys(STATUS_SPECS)


def _flags_cell(status: protocol.Status) -> Cell:
    names = protocol.flag_names(status.flags)
    # ACTIVITY and PAUSED are ordinary states; the other two mean something was
    # lost, which is what the highlight is for.
    alarming = status.has_flag(protocol.StatusFlag.OVERRUN) or status.has_flag(
        protocol.StatusFlag.TX_DROP
    )
    return Cell(" ".join(names) if names else "-", warn=alarming)


def status_cells(status: protocol.Status, stale: bool) -> dict[str, Cell]:
    return {key: render(status, stale) for key, render in STATUS_SPECS}


# --- link health -------------------------------------------------------------

LINK_SPECS: tuple[
    tuple[str, Callable[[protocol.ParserStats, LinkState], Cell]], ...
] = (
    ("Source", lambda st, link: Cell(link.source_name)),
    ("Board", lambda st, link: Cell(link.board_identity)),
    ("Telemetry rate", lambda st, link: Cell(f"{link.rate_hz:.1f} Hz")),
    ("Bytes received", lambda st, link: Cell(f"{st.bytes_in:,}")),
    ("Frames OK", lambda st, link: Cell(f"{st.frames_ok:,}")),
    (
        "CRC errors",
        lambda st, link: Cell(f"{st.crc_errors:,}", warn=st.crc_errors > 0),
    ),
    ("Bad lengths", lambda st, link: Cell(f"{st.length_errors:,}")),
    (
        "Unknown ids",
        lambda st, link: Cell(f"{st.unknown_ids:,}", warn=st.unknown_ids > 0),
    ),
    ("Resync bytes", lambda st, link: Cell(f"{st.resync_bytes:,}")),
    ("Sequence gaps", lambda st, link: Cell(f"{st.seq_gaps:,}", warn=st.seq_gaps > 0)),
    (
        "Frames lost (est.)",
        lambda st, link: Cell(
            f"{st.frames_dropped_estimate:,}", warn=st.frames_dropped_estimate > 0
        ),
    ),
    ("Recording", lambda st, link: Cell(link.recording)),
)

LINK_KEYS = _keys(LINK_SPECS)


def link_cells(stats: protocol.ParserStats, link: LinkState) -> dict[str, Cell]:
    return {key: render(stats, link) for key, render in LINK_SPECS}
