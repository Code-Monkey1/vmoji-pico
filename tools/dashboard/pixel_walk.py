"""The pixel walk: light every LED alone, in order, and score how bright it is.

A soldering check. With the whole matrix on, LEDs that share a row also share
that row's current, so a dim pixel there can be the LED, its joint, or just the
sharing. Lit alone, every LED gets the same drive, so a pixel that is still dim
or dark here is the LED or its wiring. The firmware's `X` ack names the row and
column GPIOs of each pixel, so a low score points at two specific joints.

Qt-free, like panels.py and reconnect.py: the dashboard panel and the headless
walk_pixels.py both drive this, and pytest tests it without a display.
"""

from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass

import protocol

MAX_SCORE = 5
"""Brightness scale is 0 (dark) to MAX_SCORE (as bright as the best LED)."""

_ACK = re.compile(r"^OK pixel r(\d+) c(\d+)(?: row=GP(\d+) col=GP(\d+))?\s*$")


@dataclass(frozen=True)
class PixelAck:
    """What the board confirmed it lit. GPIOs are None from the simulator."""

    row: int
    col: int
    row_gpio: int | None = None
    col_gpio: int | None = None


def walk_order() -> list[tuple[int, int]]:
    """Top-left to bottom-right, row by row, in firmware (row, col) indices.

    Firmware row 0 is the physical top and column 0 the left: checked on the
    board with this walk, see board_row_pins() in vmoji/board_pins.h.
    """
    size = protocol.MATRIX_SIZE
    return [(row, col) for row in range(size) for col in range(size)]


def parse_pixel_ack(text: str) -> PixelAck | None:
    """Decode `OK pixel r3 c5 row=GP21 col=GP9`, or None for any other line."""
    match = _ACK.match(text)
    if match is None:
        return None
    row, col, row_gpio, col_gpio = match.groups()
    return PixelAck(
        int(row),
        int(col),
        int(row_gpio) if row_gpio is not None else None,
        int(col_gpio) if col_gpio is not None else None,
    )


class PixelWalk:
    """Where the walk is, what each pixel scored, and which GPIOs drive it.

    Pure state: nothing here talks to the board. The caller sends `X` for
    `current` whenever the position changes, and feeds the ack back through
    `note_ack`, which is how GPIOs are learned rather than duplicated from
    board_pins.h.
    """

    def __init__(self) -> None:
        self.order = walk_order()
        self.index = 0
        self.ratings: dict[tuple[int, int], int] = {}
        self.gpios: dict[tuple[int, int], tuple[int | None, int | None]] = {}

    @property
    def current(self) -> tuple[int, int]:
        return self.order[self.index]

    @property
    def at_end(self) -> bool:
        return self.index == len(self.order) - 1

    def next(self) -> bool:
        """Advance one pixel. False, and no move, when already at the last."""
        if self.at_end:
            return False
        self.index += 1
        return True

    def prev(self) -> bool:
        """Step back one pixel. False, and no move, when already at the first."""
        if self.index == 0:
            return False
        self.index -= 1
        return True

    def restart(self) -> None:
        """Back to the first pixel. Scores are kept: a second pass refines them."""
        self.index = 0

    def note_ack(self, ack: PixelAck) -> None:
        if ack.row_gpio is not None or ack.col_gpio is not None:
            self.gpios[(ack.row, ack.col)] = (ack.row_gpio, ack.col_gpio)

    def rate(self, score: int) -> bool:
        """Score the current pixel, then advance. Returns whether it advanced."""
        if not 0 <= score <= MAX_SCORE:
            raise ValueError(f"score must be 0-{MAX_SCORE}, got {score}")
        self.ratings[self.current] = score
        return self.next()

    def label(self) -> str:
        """`r3 c5 · row GP21 · col GP9`, GPIOs left out until the board names them."""
        row, col = self.current
        text = f"r{row} c{col}"
        row_gpio, col_gpio = self.gpios.get((row, col), (None, None))
        if row_gpio is not None:
            text += f" · row GP{row_gpio}"
        if col_gpio is not None:
            text += f" · col GP{col_gpio}"
        score = self.ratings.get((row, col))
        if score is not None:
            text += f" · scored {score}"
        return text

    def to_csv(self) -> str:
        """Every pixel in walk order; unscored pixels and unknown GPIOs are blank."""
        out = io.StringIO()
        writer = csv.writer(out, lineterminator="\n")
        writer.writerow(["row", "col", "row_gpio", "col_gpio", "score"])
        for row, col in self.order:
            row_gpio, col_gpio = self.gpios.get((row, col), (None, None))
            score = self.ratings.get((row, col))
            writer.writerow([
                row,
                col,
                "" if row_gpio is None else row_gpio,
                "" if col_gpio is None else col_gpio,
                "" if score is None else score,
            ])
        return out.getvalue()
