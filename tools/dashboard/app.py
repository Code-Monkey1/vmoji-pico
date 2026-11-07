#!/usr/bin/env python3
"""Entry point for the vmoji telemetry dashboard.

    .venv/bin/python app.py                          # find and use a real board
    .venv/bin/python app.py --sim                    # simulator, no hardware needed
    .venv/bin/python app.py --port /dev/ttyACM0      # a specific port
    .venv/bin/python app.py --replay capture.vmc     # replay a recorded capture
    .venv/bin/python app.py --list-ports             # enumerate and exit

With no arguments the app looks for a real board and connects to it. With none
to talk to it falls back to the simulator and says so in the terminal, in the title
bar and in a banner, because a dashboard that silently shows synthetic data is
indistinguishable from one showing a broken board.
"""

from __future__ import annotations

import argparse
import os
import signal
import sys

from PySide6.QtCore import QTimer
from PySide6.QtWidgets import QApplication

import sources


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", help="serial device, e.g. /dev/ttyACM0 or COM3")
    parser.add_argument("--baud", type=int, default=115200, help="baud rate (default 115200)")
    parser.add_argument(
        "--sim",
        action="store_true",
        help="use the built-in simulator instead of hardware; the window is "
        "clearly marked so a simulated session is never mistaken for a live one",
    )
    parser.add_argument(
        "--no-probe",
        action="store_true",
        help="trust the USB id when autodetecting instead of listening for a "
        "valid frame first (faster startup, less certain)",
    )
    parser.add_argument("--replay", help="open a .vmc capture file on startup")
    parser.add_argument(
        "--record",
        help="start recording to this .vmc path immediately, without a save dialog",
    )
    parser.add_argument(
        "--error-rate",
        type=float,
        default=0.0,
        help="simulator only: fraction of frames to corrupt, to exercise the "
        "CRC and resynchronisation paths (e.g. 0.05)",
    )
    parser.add_argument("--list-ports", action="store_true", help="list serial ports and exit")
    return parser.parse_args(argv)


def _print_ports() -> int:
    candidates = sources.list_port_candidates()
    if not candidates:
        print("no USB serial ports found (legacy /dev/ttyS* nodes are hidden)")
    for candidate in candidates:
        ids = ""
        if candidate.vid is not None and candidate.pid is not None:
            ids = f"  [{candidate.vid:04x}:{candidate.pid:04x}]"
        serial_number = f"  sn={candidate.serial_number}" if candidate.serial_number else ""
        print(f"{candidate.device}\t{candidate.priority.name}{ids}\t"
              f"{candidate.description}{serial_number}")

    for serial_number in sources.detect_bootsel_boards():
        print(f"(a board is in BOOTSEL, firmware not running: sn={serial_number})")
    return 0


def resolve_initial_source(args: argparse.Namespace) -> sources.SourceSelection:
    """Decide what to connect to before any window exists.

    Explicit flags win; otherwise we look for hardware and only fall back to the
    simulator when there is genuinely nothing to talk to.
    """
    if args.sim:
        return sources.SIMULATOR
    if args.port:
        return sources.SourceSelection("serial", args.port)

    candidate = sources.autodetect_port(baudrate=args.baud, probe=not args.no_probe)
    if candidate is not None:
        print(f"found {candidate.label}")
        return sources.SourceSelection("serial", candidate.device)

    for serial_number in sources.detect_bootsel_boards():
        print(f"a board is in BOOTSEL (sn={serial_number}); it is not running firmware")

    seen = sources.list_port_candidates()
    if seen:
        print("no port produced valid telemetry:")
        for entry in seen:
            print(f"  {entry.label}")
    else:
        print("no board detected")
    print("falling back to the simulator; pass --sim to select it deliberately")
    return sources.SIMULATOR


NO_DISPLAY_MESSAGE = """\
No display: the dashboard needs a graphical session to open its window.
  - Over SSH: use ssh -X, or run it on the machine's desktop.
  - Virtual display: xvfb-run -a .venv/bin/python app.py --sim
  - No window at all: QT_QPA_PLATFORM=offscreen .venv/bin/python app.py --sim
verify_link.py and walk_pixels.py need no display."""


def has_display(env: os._Environ[str] | dict[str, str] = os.environ) -> bool:
    """Qt aborts the process when it finds no display, with an error about plugins
    that points at the wrong problem, so check first. QT_QPA_PLATFORM means the
    caller has picked a platform themselves (offscreen, for instance)."""
    return any(env.get(name) for name in ("DISPLAY", "WAYLAND_DISPLAY", "QT_QPA_PLATFORM"))


def quit_on_ctrl_c(window) -> None:
    """Make Ctrl+C close the window the normal way, which saves the layout and
    finishes a recording.

    Python only runs signal handlers between bytecodes, and Qt's C++ event loop
    never returns to the interpreter on its own, so without the timer the handler
    would wait for the next mouse move. The timer just wakes the interpreter up.

    The close is queued rather than done in the handler, so it runs inside the event
    loop: a signal arriving just before app.exec() would otherwise close the window
    while nothing is listening for the last window closing, and the app would never quit.
    """
    signal.signal(signal.SIGINT, lambda *_: QTimer.singleShot(0, window.close))
    wake = QTimer(window)
    wake.timeout.connect(lambda: None)
    wake.start(200)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.list_ports:
        return _print_ports()

    if not has_display():
        print(NO_DISPLAY_MESSAGE, file=sys.stderr)
        return 2

    selection = (
        sources.SourceSelection("replay", args.replay)
        if args.replay
        else resolve_initial_source(args)
    )

    app = QApplication(sys.argv[:1])
    app.setApplicationName("vmoji telemetry dashboard")
    app.setOrganizationName("vmoji")

    # Imported here so --list-ports works without constructing any Qt widgets.
    from main_window import MainWindow

    window = MainWindow(
        initial_selection=selection,
        baudrate=args.baud,
        error_rate=args.error_rate,
    )
    window.show()
    quit_on_ctrl_c(window)

    if args.record:
        window.start_recording(args.record)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
