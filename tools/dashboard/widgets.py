"""Custom widgets: the LED matrix mimic and a compact key/value readout.

Both are pure views. They hold no state beyond what they were last told to
display, which keeps the data flow one-directional: source to parser to model to
view.
"""

from __future__ import annotations

from PySide6.QtCore import QRectF, Qt
from PySide6.QtGui import QColor, QFont, QPainter, QPen, QRadialGradient
from PySide6.QtWidgets import (
    QFrame,
    QGridLayout,
    QLabel,
    QSizePolicy,
    QWidget,
)


class MatrixView(QWidget):
    """Mirrors the 8x8 LED matrix as reported by the firmware.

    This is the panel that turns the tool from a set of graphs into a debugger:
    when the physical display shows the wrong thing, this answers whether the
    framebuffer is wrong or the scan-out is wrong. That distinction is most of
    bring-up.
    """

    LED_ON = QColor(255, 96, 64)
    LED_OFF = QColor(38, 40, 46)
    GRID = QColor(58, 62, 70)

    def __init__(self, parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self._grid = [[False] * 8 for _ in range(8)]
        self._stale = True
        self.setMinimumSize(150, 150)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Expanding)

    def set_grid(self, grid: list[list[bool]]) -> None:
        self._grid = grid
        self._stale = False
        self.update()

    def set_stale(self, stale: bool) -> None:
        """Dim the display when telemetry has stopped arriving, so a frozen panel
        is visibly frozen rather than quietly misleading."""
        if stale != self._stale:
            self._stale = stale
            self.update()

    def clear(self) -> None:
        self._grid = [[False] * 8 for _ in range(8)]
        self._stale = True
        self.update()

    def paintEvent(self, event) -> None:  # noqa: N802  (Qt naming)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)

        side = min(self.width(), self.height())
        cell = side / 8.0
        x_offset = (self.width() - side) / 2.0
        y_offset = (self.height() - side) / 2.0
        radius = cell * 0.34
        opacity = 0.35 if self._stale else 1.0
        painter.setOpacity(opacity)

        painter.setPen(QPen(self.GRID, 1))
        for row in range(8):
            for col in range(8):
                centre_x = x_offset + col * cell + cell / 2.0
                centre_y = y_offset + row * cell + cell / 2.0
                rect = QRectF(centre_x - radius, centre_y - radius, radius * 2, radius * 2)
                if self._grid[row][col]:
                    glow = QRadialGradient(centre_x, centre_y, radius * 1.9)
                    glow.setColorAt(0.0, self.LED_ON)
                    glow.setColorAt(0.45, self.LED_ON.darker(130))
                    glow.setColorAt(1.0, QColor(255, 96, 64, 0))
                    painter.setBrush(glow)
                    painter.setPen(Qt.PenStyle.NoPen)
                    painter.drawEllipse(
                        QRectF(centre_x - radius * 1.9, centre_y - radius * 1.9,
                               radius * 3.8, radius * 3.8)
                    )
                    painter.setBrush(self.LED_ON)
                else:
                    painter.setBrush(self.LED_OFF)
                painter.setPen(QPen(self.GRID, 1))
                painter.drawEllipse(rect)
        painter.end()


class KeyValuePanel(QFrame):
    """A two-column readout of labelled values.

    Rows are created once and only their text is updated, because recreating
    widgets at the repaint rate is the classic way to make a Qt dashboard slow.
    """

    def __init__(self, keys: list[str], parent: QWidget | None = None) -> None:
        super().__init__(parent)
        self.setFrameShape(QFrame.Shape.NoFrame)

        layout = QGridLayout(self)
        layout.setContentsMargins(4, 4, 4, 4)
        layout.setVerticalSpacing(2)
        layout.setHorizontalSpacing(10)
        layout.setColumnStretch(1, 1)

        value_font = QFont("monospace")
        value_font.setStyleHint(QFont.StyleHint.TypeWriter)

        self._values: dict[str, QLabel] = {}
        for row, key in enumerate(keys):
            name = QLabel(key)
            name.setStyleSheet("color: #9aa0aa;")
            value = QLabel("--")
            value.setFont(value_font)
            value.setAlignment(Qt.AlignmentFlag.AlignRight | Qt.AlignmentFlag.AlignVCenter)
            value.setTextInteractionFlags(Qt.TextInteractionFlag.TextSelectableByMouse)
            layout.addWidget(name, row, 0)
            layout.addWidget(value, row, 1)
            self._values[key] = value

    def set_value(self, key: str, text: str, *, warn: bool = False) -> None:
        label = self._values.get(key)
        if label is None:
            return
        if label.text() != text:
            label.setText(text)
        label.setStyleSheet("color: #ffb347;" if warn else "color: #e6e8ec;")

    def set_values(self, values: dict[str, str]) -> None:
        for key, text in values.items():
            self.set_value(key, text)

    def clear_values(self) -> None:
        for key in self._values:
            self.set_value(key, "--")
