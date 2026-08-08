#!/usr/bin/env python3
"""Entry point for the vmoji telemetry dashboard.

    .venv/bin/python app.py                          # simulator, no hardware needed
    .venv/bin/python app.py --port /dev/ttyACM0      # live board over USB CDC
    .venv/bin/python app.py --replay capture.vmc     # replay a recorded capture
    .venv/bin/python app.py --error-rate 0.05        # inject corruption on purpose
    .venv/bin/python app.py --list-ports             # enumerate and exit
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


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    if args.list_ports:
        ports = sources.list_serial_ports()
        if not ports:
            print("no USB serial ports found (legacy /dev/ttyS* nodes are hidden)")
        for device, description in ports:
            print(f"{device}\t{description}")
        return 0

    app = QApplication(sys.argv[:1])
    app.setApplicationName("vmoji telemetry dashboard")

    # Imported here so --list-ports works without constructing any Qt widgets.
    from main_window import MainWindow

    window = MainWindow(
        initial_source="serial" if args.port else "sim",
        port=args.port,
        baudrate=args.baud,
        error_rate=args.error_rate,
    )
    window.show()

    if args.record:
        window.start_recording(args.record)

    if args.replay:
        try:
            source = sources.ReplaySource(args.replay, speed=1.0)
        except sources.SourceError as exc:
            print(f"could not open {args.replay}: {exc}", file=sys.stderr)
            return 1
        window.source_combo.addItem(f"Replay  -  {args.replay}", ("replay", args.replay))
        window.source_combo.setCurrentIndex(window.source_combo.count() - 1)
        window._start_worker(source)

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
