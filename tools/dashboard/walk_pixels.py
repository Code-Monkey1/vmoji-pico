#!/usr/bin/env python3
"""Light every LED of the matrix alone, one after the other.

A soldering check. With the whole matrix on, LEDs that share a row also share
that row's current, so a dim pixel there can be the LED, its joint, or just the
sharing. Lit alone, every LED gets the same drive, so a pixel that is still dim
or dark here is the LED or its wiring, and the GPIOs printed next to it say
which joints to look at.

Order is top-left to bottom-right, one row at a time. Rows are numbered
bottom-to-top and columns left-to-right as mounted (see vmoji/board_pins.h), so
the walk starts at row 7, column 0. If the first pixel is not top-left, the
orientation comment there is wrong for your build: tell it apart by the r/c
printed for each step.

    .venv/bin/python walk_pixels.py --port /dev/ttyACM0              # 1 s per LED
    .venv/bin/python walk_pixels.py --port /dev/ttyACM0 --delay 0.3
    .venv/bin/python walk_pixels.py --port /dev/ttyACM0 --step       # Enter to advance

In --step mode, type a note before Enter (e.g. "dim", "dead", "flicker") to flag
the lit pixel; flagged pixels are summarised with their GPIOs at the end. Type
"q" to stop. The display is blanked on exit.

Needs firmware with the `X <row> <col>` command.
"""

from __future__ import annotations

import argparse
import contextlib
import sys
import time

import protocol
import sources

ACK_TIMEOUT_S = 1.0


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", help="serial device; omit to run against the simulator")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--delay", type=float, default=1.0,
                        help="seconds each LED stays lit (ignored with --step)")
    parser.add_argument("--step", action="store_true",
                        help="advance on Enter, and record a note per pixel")
    return parser.parse_args(argv)


def walk_order() -> list[tuple[int, int]]:
    """Top-left to bottom-right, row by row, in firmware (row, col) indices."""
    size = protocol.MATRIX_SIZE
    return [(row, col) for row in range(size - 1, -1, -1) for col in range(size)]


def send_and_wait(source: sources.Source, parser: protocol.FrameParser,
                  command: protocol.Command) -> str | None:
    """Send one command and return its ack text, or None if none arrived.

    Telemetry keeps streaming meanwhile; everything that is not a text reply is
    dropped here, since this tool only cares whether the board did as told.
    """
    source.write(command.encode())
    deadline = time.monotonic() + ACK_TIMEOUT_S
    while time.monotonic() < deadline:
        for message in parser.feed(source.read(4096)):
            if isinstance(message, protocol.TextMessage) and (
                message.text.startswith("OK") or message.text.startswith("ERR")
            ):
                return message.text
    return None


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        source: sources.Source = (
            sources.SerialSource(args.port, args.baud) if args.port else sources.SimSource()
        )
    except sources.SourceError as exc:
        print(f"FAIL  could not open source: {exc}")
        return 2

    parser = protocol.FrameParser()
    notes: list[tuple[str, str]] = []
    status = 0
    try:
        for index, (row, col) in enumerate(walk_order(), start=1):
            ack = send_and_wait(source, parser, protocol.cmd_pixel(row, col))
            if ack is None:
                print(f"FAIL  no reply to X {row} {col}: is the firmware running?")
                status = 1
                break
            if ack.startswith("ERR"):
                print(f"FAIL  board rejected X {row} {col}: {ack}")
                if "unknown" in ack:
                    print("      This firmware predates the X command: flash a newer build.")
                status = 1
                break

            # "OK pixel r3 c5 row=GP21 col=GP11" -> "r3 c5 row=GP21 col=GP11"
            label = ack.removeprefix("OK pixel ").strip()
            prompt = f"[{index:2d}/64] {label}"
            if args.step:
                note = input(f"{prompt}  note> ").strip()
                if note.lower() == "q":
                    break
                if note:
                    notes.append((label, note))
            else:
                print(prompt, flush=True)
                time.sleep(args.delay)
    except KeyboardInterrupt:
        print()
    finally:
        with contextlib.suppress(sources.SourceError):
            send_and_wait(source, parser, protocol.cmd_blank())
        source.close()

    if notes:
        print("\nflagged pixels:")
        for label, note in notes:
            print(f"  {label:28s} {note}")
    return status


if __name__ == "__main__":
    sys.exit(main())
