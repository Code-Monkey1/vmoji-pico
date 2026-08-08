"""Bounded time-series store for the dashboard.

Two ideas carry this module.

**Bounded memory.** Every series is a ``deque`` with a ``maxlen``, so appending is
O(1) and old samples fall off the back automatically. A monitoring tool gets left
running for days; an unbounded list is a slow memory leak with a plausible
excuse. At 10 Hz a 12000-sample window is 20 minutes of history for a few hundred
kilobytes.

**No Qt.** This is plain Python, which means the whole data path - parse, store,
derive - is unit testable without starting an event loop or a window.

The model is written from the reader thread (via a queued signal, so the write
actually lands on the GUI thread) and read by the repaint timer. Those are the
same thread, so no locking is needed here. That is a property worth stating out
loud rather than leaving implicit, because it is the reason this code can be
lock-free.
"""

from __future__ import annotations

import collections
import time
from dataclasses import dataclass, field
from typing import Deque, Iterable

import protocol


@dataclass
class Series:
    """One named channel of (time, value) samples."""

    label: str
    units: str = ""
    maxlen: int = 12_000
    t: Deque[float] = field(init=False)
    v: Deque[float] = field(init=False)

    def __post_init__(self) -> None:
        self.t = collections.deque(maxlen=self.maxlen)
        self.v = collections.deque(maxlen=self.maxlen)

    def append(self, timestamp: float, value: float) -> None:
        self.t.append(timestamp)
        self.v.append(value)

    def clear(self) -> None:
        self.t.clear()
        self.v.clear()

    def __len__(self) -> int:
        return len(self.v)

    @property
    def latest(self) -> float | None:
        return self.v[-1] if self.v else None

    def window(self, seconds: float) -> tuple[list[float], list[float]]:
        """The trailing ``seconds`` of data, as lists ready for ``setData``."""
        if not self.t:
            return [], []
        cutoff = self.t[-1] - seconds
        times = list(self.t)
        values = list(self.v)
        # Samples are appended in order, so a reverse scan finds the cut point
        # without a full sort or a binary-search import.
        start = 0
        for index in range(len(times) - 1, -1, -1):
            if times[index] < cutoff:
                start = index + 1
                break
        return times[start:], values[start:]

    def stats(self, seconds: float = 10.0) -> tuple[float, float, float] | None:
        """(min, mean, max) over the trailing window, or None if empty."""
        _, values = self.window(seconds)
        if not values:
            return None
        return min(values), sum(values) / len(values), max(values)


class TelemetryModel:
    """Everything the views draw, and nothing about how they draw it."""

    SERIES_MAXLEN = 12_000

    def __init__(self, maxlen: int | None = None) -> None:
        n = maxlen or self.SERIES_MAXLEN
        self.refresh_hz = Series("Refresh rate", "Hz", n)
        self.period_mean_us = Series("Scan period (mean)", "us", n)
        self.period_min_us = Series("Scan period (min)", "us", n)
        self.period_max_us = Series("Scan period (max)", "us", n)
        self.jitter_pp_us = Series("Jitter (peak-peak)", "us", n)
        self.die_temp_c = Series("Die temperature", "C", n)
        self.rx_bytes = Series("Bytes received", "B", n)

        self.latest_status: protocol.Status | None = None
        self.latest_framebuffer: protocol.FrameBuffer | None = None
        self.log_lines: Deque[str] = collections.deque(maxlen=500)

        self.t0: float | None = None
        self.status_count = 0
        self.framebuffer_count = 0
        self.first_status_time: float | None = None

        # Rolling estimate of the telemetry arrival rate, for the status bar.
        self._status_arrivals: Deque[float] = collections.deque(maxlen=50)

    # -- ingest ------------------------------------------------------------

    def add_message(self, message: protocol.Message) -> None:
        if isinstance(message, protocol.Status):
            self._add_status(message)
        elif isinstance(message, protocol.FrameBuffer):
            self.latest_framebuffer = message
            self.framebuffer_count += 1
        elif isinstance(message, protocol.TextMessage):
            tag = "ACK" if message.msg_id is protocol.MsgId.ACK else "LOG"
            self.log_lines.append(f"[{self._stamp(message.host_time)}] {tag}  {message.text}")
        elif isinstance(message, protocol.UnknownMessage):
            self.log_lines.append(
                f"[{self._stamp(message.host_time)}] ??   id=0x{message.raw_id:02x} "
                f"len={len(message.payload)} (unrecognised message)"
            )

    def add_messages(self, messages: Iterable[protocol.Message]) -> None:
        for message in messages:
            self.add_message(message)

    def _add_status(self, status: protocol.Status) -> None:
        if self.t0 is None:
            self.t0 = status.host_time
            self.first_status_time = status.host_time

        # Plot against seconds since the first sample. Absolute monotonic values
        # are large and make pyqtgraph's axis labels unreadable.
        t = status.host_time - self.t0

        self.refresh_hz.append(t, status.refresh_hz)
        self.period_mean_us.append(t, status.period_mean_us)
        self.period_min_us.append(t, status.period_min_us)
        self.period_max_us.append(t, status.period_max_us)
        self.jitter_pp_us.append(t, status.jitter_pp_us)
        self.die_temp_c.append(t, status.die_temp_c)
        self.rx_bytes.append(t, status.rx_bytes)

        self.latest_status = status
        self.status_count += 1
        self._status_arrivals.append(status.host_time)

    # -- derived -----------------------------------------------------------

    @property
    def status_rate_hz(self) -> float:
        """Observed telemetry arrival rate, independent of what the firmware
        claims. Useful precisely when the two disagree."""
        if len(self._status_arrivals) < 2:
            return 0.0
        span = self._status_arrivals[-1] - self._status_arrivals[0]
        if span <= 0:
            return 0.0
        return (len(self._status_arrivals) - 1) / span

    @property
    def elapsed_s(self) -> float:
        if self.t0 is None or not self.refresh_hz.t:
            return 0.0
        return self.refresh_hz.t[-1]

    def all_series(self) -> tuple[Series, ...]:
        return (
            self.refresh_hz,
            self.period_mean_us,
            self.period_min_us,
            self.period_max_us,
            self.jitter_pp_us,
            self.die_temp_c,
            self.rx_bytes,
        )

    def clear(self) -> None:
        for series in self.all_series():
            series.clear()
        self.latest_status = None
        self.latest_framebuffer = None
        self.log_lines.clear()
        self.t0 = None
        self.status_count = 0
        self.framebuffer_count = 0
        self._status_arrivals.clear()

    @staticmethod
    def _stamp(_host_time: float) -> str:
        # Wall clock, because log lines are read by humans correlating against
        # a bench clock, not against the monotonic timebase used for plotting.
        return time.strftime("%H:%M:%S")
