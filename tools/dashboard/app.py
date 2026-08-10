#!/usr/bin/env python3
"""Entry point for the vmoji telemetry dashboard.

    .venv/bin/python app.py                          # find and use a real board
    .venv/bin/python app.py --sim                    # simulator, no hardware needed
    .venv/bin/python app.py --port /dev/ttyACM0      # a specific port
    .venv/bin/python app.py --replay capture.vmc     # replay a recorded capture
    .venv/bin/python app.py --list-ports             # enumerate and exit

With no arguments the app looks for a real board and connects to it. The
simulator is opt-in, because a dashboard that silently shows synthetic data is
indistinguishable from one showing a broken board.
"""

from __future__ import annotations

import argparse
import sys

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


def resolve_initial_source(args: argparse.Namespace) -> tuple[str, str | None]:
    """Decide what to connect to before any window exists.

    Explicit flags win; otherwise we look for hardware and only fall back to the
    simulator when there is genuinely nothing to talk to.
    """
    if args.sim:
        return ("sim", None)
    if args.port:
        return ("serial", args.port)

    candidate = sources.autodetect_port(baudrate=args.baud, probe=not args.no_probe)
    if candidate is not None:
        print(f"found {candidate.label}")
        return ("serial", candidate.device)

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
    return ("sim", None)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.list_ports:
        return _print_ports()

    selection = ("replay", args.replay) if args.replay else resolve_initial_source(args)

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

    if args.record:
        window.start_recording(args.record)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
