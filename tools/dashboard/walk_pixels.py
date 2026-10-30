#!/usr/bin/env python3
"""Light every LED of the matrix alone, one after the other: the headless pixel walk.

The dashboard's "Pixel walk" panel is the main way to run this and lets you
score each LED; this is the same walk for a terminal, or for a board without
a display attached. See pixel_walk.py for why lighting LEDs alone isolates bad
joints from current sharing.

Order is top-left to bottom-right, one row at a time.

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

import pixel_walk
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
        walk = pixel_walk.PixelWalk()
        while True:
            row, col = walk.current
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

            parsed = pixel_walk.parse_pixel_ack(ack)
            if parsed is not None:
                walk.note_ack(parsed)
            label = walk.label()
            prompt = f"[{walk.index + 1:2d}/{len(walk.order)}] {label}"
            if args.step:
                note = input(f"{prompt}  note> ").strip()
                if note.lower() == "q":
                    break
                if note:
                    notes.append((label, note))
            else:
                print(prompt, flush=True)
                time.sleep(args.delay)
            if not walk.next():
                break
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
