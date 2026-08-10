"""When to retry a link that dropped, and what to say while waiting.

A bumped USB cable mid-demo should not end the session: the board is usually
back within a second. The retry rules are pure state - a target, a delay and a
doubling bound - so they live here rather than inside the window, where they
could only be exercised by starting an event loop and unplugging something.

The window still owns the ``QTimer``; this owns the decision of what to retry
and how long to wait before the next attempt.
"""

from __future__ import annotations

from sources import SourceSelection

MIN_DELAY_S = 0.5
MAX_DELAY_S = 5.0


class ReconnectPolicy:
    """Bounded exponential backoff against one remembered target."""

    def __init__(
        self, min_delay_s: float = MIN_DELAY_S, max_delay_s: float = MAX_DELAY_S
    ) -> None:
        self._min_delay_s = min_delay_s
        self._max_delay_s = max_delay_s
        self.target: SourceSelection | None = None
        self.delay_s = min_delay_s

    @property
    def active(self) -> bool:
        return self.target is not None

    def arm(self, target: SourceSelection) -> None:
        """Begin retrying ``target``, restarting the backoff if it is new.

        Keeping the delay when the same device fails again is what makes the
        backoff mean anything: a board that is genuinely gone should be polled
        less often, not reset to half a second on every attempt.
        """
        if target != self.target:
            self.delay_s = self._min_delay_s
        self.target = target

    def backoff(self) -> float:
        """Double the wait, up to the ceiling, and return the new delay.

        The ceiling matters: twenty failures on an unplugged board must not push
        the next retry minutes into the future, because the person who plugs it
        back in expects it to be noticed.
        """
        self.delay_s = min(self._max_delay_s, self.delay_s * 2)
        return self.delay_s

    def reset(self) -> None:
        self.target = None
        self.delay_s = self._min_delay_s

    def message(self, remaining_ms: int) -> str:
        """The status line to show while a retry is pending."""
        if self.target is None:
            return "disconnected"
        device = self.target.device
        if remaining_ms <= 0:
            return f"{device} lost - retrying now"
        return f"{device} lost - reconnecting in {remaining_ms / 1000:.1f} s"
