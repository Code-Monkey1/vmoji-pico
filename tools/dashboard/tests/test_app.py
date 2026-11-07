"""The app as a process (no display, Ctrl+C) and its theme."""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

import app
import sources
import theme

DASHBOARD_DIR = Path(__file__).resolve().parents[1]


def _clean_env(tmp_path: Path, **extra: str) -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if key not in ("DISPLAY", "WAYLAND_DISPLAY", "QT_QPA_PLATFORM")
    }
    # QSettings lives here: a test run must not overwrite the developer's saved layout.
    env["XDG_CONFIG_HOME"] = str(tmp_path / "config")
    env.update(extra)
    return env


def _run_app(env: dict[str, str], *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, "app.py", *args],
        cwd=DASHBOARD_DIR,
        env=env,
        capture_output=True,
        text=True,
        timeout=30,
    )


@pytest.mark.parametrize(
    ("env", "expected"),
    [
        ({}, False),
        ({"DISPLAY": ""}, False),
        ({"DISPLAY": ":0"}, True),
        ({"WAYLAND_DISPLAY": "wayland-0"}, True),
        ({"QT_QPA_PLATFORM": "offscreen"}, True),
    ],
)
def test_has_display(env, expected):
    assert app.has_display(env) is expected


def test_no_display_explains_itself_instead_of_crashing(tmp_path):
    result = _run_app(_clean_env(tmp_path), "--sim")

    assert result.returncode == 2
    assert "No display" in result.stderr
    assert "xvfb-run" in result.stderr
    assert "QT_QPA_PLATFORM=offscreen" in result.stderr


def test_listing_ports_needs_no_display(tmp_path):
    assert _run_app(_clean_env(tmp_path), "--list-ports").returncode == 0


def test_ctrl_c_closes_cleanly_and_keeps_the_recording(tmp_path):
    capture = tmp_path / "session.vmc"
    process = subprocess.Popen(
        [sys.executable, "app.py", "--sim", "--record", str(capture)],
        cwd=DASHBOARD_DIR,
        env=_clean_env(tmp_path, QT_QPA_PLATFORM="offscreen"),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline and not (capture.exists() and capture.stat().st_size):
            assert process.poll() is None, process.stderr.read()
            time.sleep(0.05)
        assert capture.stat().st_size, "the app never started recording"

        process.send_signal(signal.SIGINT)
        _, stderr = process.communicate(timeout=10)
    finally:
        process.kill()

    assert process.returncode == 0, stderr
    assert sources.read_capture(capture)


def _lightness(hex_color: str) -> int:
    from PySide6.QtGui import QColor

    return QColor(hex_color).lightness()


def test_window_is_dark_even_on_a_light_desktop(qt_app, make_window):
    """Readouts use light text. On a light system palette they used to be unreadable."""
    from PySide6.QtGui import QColor, QPalette

    light = QPalette(QColor("#f0f0f0"))
    qt_app.setPalette(light)

    window = make_window()
    window.show()
    qt_app.processEvents()

    assert qt_app.style().objectName().lower() == "fusion"
    for role in (QPalette.ColorRole.Window, QPalette.ColorRole.Base, QPalette.ColorRole.Button):
        assert qt_app.palette().color(role).lightness() < 70, role
    for role in (
        QPalette.ColorRole.WindowText,
        QPalette.ColorRole.Text,
        QPalette.ColorRole.ButtonText,
    ):
        assert qt_app.palette().color(role).lightness() > 180, role
    # What is actually on screen, not just what the palette claims.
    image = window.grab().toImage()
    samples = sorted(
        image.pixelColor(x, y).lightness()
        for x in range(10, image.width(), 40)
        for y in range(10, image.height(), 40)
    )
    assert samples[len(samples) // 2] < 70


def test_readout_text_contrasts_with_the_window():
    assert _lightness(theme.TEXT) - _lightness(theme.BACKGROUND) > 150
    assert _lightness(theme.TEXT_MUTED) - _lightness(theme.BACKGROUND) > 90
    assert _lightness(theme.WARNING) - _lightness(theme.BACKGROUND) > 100
