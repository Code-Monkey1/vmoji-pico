"""The dashboard's look: its one dark theme and every color it uses.

Dark is the only theme, on purpose. It is one style to maintain, and it doesn't depend on the
desktop's: hard-coded light text on a light system palette was unreadable.
"""

from __future__ import annotations

import pyqtgraph as pg
from PySide6.QtGui import QColor, QPalette
from PySide6.QtWidgets import QApplication, QToolTip

BACKGROUND = "#1b1d22"
BASE = "#14161a"  # text fields and lists, a step darker than the window
BUTTON = "#2a2d34"
HIGHLIGHT = "#3d6ea5"
LINK = "#5ec8ff"

TEXT = "#e6e8ec"
TEXT_MUTED = "#9aa0aa"
TEXT_DISABLED = "#6b7078"
PLOT_FOREGROUND = "#c8ccd4"
WARNING = "#ffb347"

BANNER_BACKGROUND = "#7a4a12"
BANNER_TEXT = "#ffd9a0"

SERIES_REFRESH = "#5ec8ff"
SERIES_RPM = "#63e6be"
SERIES_PERIOD_MAX = "#ff6b6b"
SERIES_PERIOD_MEAN = "#ffd166"
SERIES_PERIOD_MIN = "#8ce99a"
SERIES_JITTER = "#c084fc"
SERIES_JITTER_FILL = (192, 132, 252, 40)
SERIES_TEMPERATURE = "#ffa94d"

LED_ON = (255, 96, 64)
LED_OFF = (38, 40, 46)
LED_GRID = (58, 62, 70)


def _palette() -> QPalette:
    palette = QPalette()
    active = {
        QPalette.ColorRole.Window: BACKGROUND,
        QPalette.ColorRole.WindowText: TEXT,
        QPalette.ColorRole.Base: BASE,
        QPalette.ColorRole.AlternateBase: BACKGROUND,
        QPalette.ColorRole.Text: TEXT,
        QPalette.ColorRole.PlaceholderText: TEXT_MUTED,
        QPalette.ColorRole.Button: BUTTON,
        QPalette.ColorRole.ButtonText: TEXT,
        QPalette.ColorRole.BrightText: WARNING,
        QPalette.ColorRole.ToolTipBase: BUTTON,
        QPalette.ColorRole.ToolTipText: TEXT,
        QPalette.ColorRole.Highlight: HIGHLIGHT,
        QPalette.ColorRole.HighlightedText: TEXT,
        QPalette.ColorRole.Link: LINK,
        QPalette.ColorRole.LinkVisited: SERIES_JITTER,
        # Fusion derives its bevels from these.
        QPalette.ColorRole.Light: "#3a3e46",
        QPalette.ColorRole.Midlight: "#32353d",
        QPalette.ColorRole.Mid: "#26282e",
        QPalette.ColorRole.Dark: "#121317",
        QPalette.ColorRole.Shadow: "#000000",
    }
    for role, color in active.items():
        palette.setColor(role, QColor(color))
    for role in (
        QPalette.ColorRole.WindowText,
        QPalette.ColorRole.Text,
        QPalette.ColorRole.ButtonText,
        QPalette.ColorRole.HighlightedText,
    ):
        palette.setColor(QPalette.ColorGroup.Disabled, role, QColor(TEXT_DISABLED))
    return palette


def apply_theme() -> None:
    """Make the running application dark, whatever the desktop's theme is.

    A dark palette because this is a monitoring tool that sits open all day, and pyqtgraph
    defaults to a white canvas that is punishing next to it. Fusion because it honors the
    palette on every desktop; native styles may not.
    """
    pg.setConfigOptions(
        antialias=False,  # off by design: dense polylines cost more than they gain
        background=BACKGROUND,
        foreground=PLOT_FOREGROUND,
    )
    app = QApplication.instance()
    app.setStyle("Fusion")
    palette = _palette()
    app.setPalette(palette)
    QToolTip.setPalette(palette)
