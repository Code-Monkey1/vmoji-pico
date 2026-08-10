"""Shared test bootstrap and fixtures.

The dashboard modules are flat files in the parent directory rather than an
installed package, so the path has to be extended before they can be imported.
Doing it here means each test module can just ``import protocol`` at the top,
the way any other reader of the code would expect.
"""

from __future__ import annotations

import os
import sys
import time

import pytest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


@pytest.fixture(scope="session")
def qt_app():
    """One QApplication for the session, isolated from the real dashboard.

    Qt permits only a single instance per process, and without distinct
    organisation and application names the window's QSettings would collide
    with the installed dashboard's - a test run would restore, and then
    overwrite, the developer's saved window layout.
    """
    pytest.importorskip("PySide6")
    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    from PySide6.QtCore import QCoreApplication
    from PySide6.QtWidgets import QApplication

    app = QApplication.instance() or QApplication([])
    QCoreApplication.setOrganizationName("vmoji-tests")
    QCoreApplication.setApplicationName("dashboard-tests")
    return app


@pytest.fixture
def pump(qt_app):
    """Run the event loop for a while; the reader lives on another thread."""

    def _pump(seconds: float) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            qt_app.processEvents()
            time.sleep(0.005)

    return _pump


@pytest.fixture
def make_window(qt_app):
    """Build MainWindows that are torn down even when a test fails.

    A window left open keeps a reader thread and a pending reconnect timer
    alive, which then fires into the next test; teardown here rather than a
    try/finally in every test is what keeps that from being one forgotten
    block away.
    """
    windows = []

    def _make(initial_selection=("sim", None), **kwargs):
        from main_window import MainWindow

        window = MainWindow(initial_selection=initial_selection, **kwargs)
        windows.append(window)
        return window

    yield _make

    for window in windows:
        window._cancel_reconnect()
        window.close()
    qt_app.processEvents()
