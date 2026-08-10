#!/usr/bin/env python3
"""Headless bring-up check for the telemetry link.

Run this immediately after flashing, before opening the GUI. If something is
wrong - wrong port, wrong baud, firmware not running, TX and RX swapped - this
says so in one line instead of leaving you staring at an empty plot wondering
whether the bug is in the firmware or the dashboard.

    .venv/bin/python verify_link.py                     # against the simulator
    .venv/bin/python verify_link.py --port /dev/ttyACM0
    .venv/bin/python verify_link.py --port /dev/ttyACM0 --command "D 900"

Exits non-zero if no valid telemetry arrived, so it is usable in a script.
"""

from __future__ import annotations

import argparse
import sys
import time

import protocol
import sources


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", help="serial device; omit to test the simulator")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--seconds", type=float, default=5.0, help="how long to listen")
    parser.add_argument("--command", help="send this command line once, then observe")
    parser.add_argument("--verbose", action="store_true", help="print every message")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)

    try:
        source: sources.Source = (
            sources.SerialSource(args.port, args.baud)
            if args.port
            else sources.SimSource()
        )
    except sources.SourceError as exc:
        print(f"FAIL  could not open source: {exc}")
        if args.port:
            candidates = sources.list_port_candidates()
            if candidates:
                print("\nUSB serial ports currently available, best first:")
                for candidate in candidates:
                    print(f"  {candidate.label}")
                print("\nIf the port exists but is refused: are you in the 'dialout' group?")
            else:
                print("\nNo USB serial ports found (legacy /dev/ttyS* nodes are hidden).")
                print("Is the board plugged in, and out of BOOTSEL mode? After flashing by")
                print("drag-and-drop it reboots on its own; after BOOTSEL it does not.")
        return 2

    print(f"listening to {source.name} for {args.seconds:.1f} s")
    parser = protocol.FrameParser()
    statuses: list[protocol.Status] = []
    texts: list[str] = []

    if args.command:
        source.write((args.command.strip() + "\n").encode("ascii"))
        print(f"sent: {args.command.strip()}")

    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        try:
            chunk = source.read(4096)
        except sources.SourceError as exc:
            print(f"FAIL  link dropped: {exc}")
            return 2
        for message in parser.feed(chunk):
            if args.verbose:
                print(f"  {message}")
            if isinstance(message, protocol.Status):
                statuses.append(message)
            elif isinstance(message, protocol.TextMessage):
                texts.append(message.text)

    source.close()

    stats = parser.stats
    print()
    print(f"bytes received     {stats.bytes_in:,}")
    print(f"frames OK          {stats.frames_ok:,}")
    print(f"CRC errors         {stats.crc_errors}")
    print(f"bad lengths        {stats.length_errors}")
    print(f"resync bytes       {stats.resync_bytes:,}  (the ASCII boot banner counts here)")
    print(f"sequence gaps      {stats.seq_gaps}")
    print(f"status messages    {len(statuses)}")

    for text in texts[:5]:
        print(f"device said        {text!r}")

    if not statuses:
        print()
        print("FAIL  no status messages decoded.")
        if stats.bytes_in == 0:
            print("      Nothing arrived at all. Check the port, and that the firmware is")
            print("      running (the board is not sitting in BOOTSEL mode).")
        elif stats.frames_ok == 0:
            print("      Bytes arrived but no frame ever validated. If resync bytes are")
            print("      climbing steadily, the baud rate is probably wrong.")
        return 1

    first, last = statuses[0], statuses[-1]
    span = last.host_time - first.host_time
    observed_hz = (len(statuses) - 1) / span if span > 0 else 0.0

    print()
    print(f"observed telemetry rate   {observed_hz:.2f} Hz   (firmware target is 10 Hz)")
    print(f"reported refresh rate     {last.refresh_hz:.2f} Hz")
    print(f"scan period               {last.period_min_us} / {last.period_mean_us} / "
          f"{last.period_max_us} us  (min/mean/max)")
    print(f"jitter peak-to-peak       {last.jitter_pp_us} us")
    print(f"die temperature           {last.die_temp_c:.2f} C")
    print(f"row dwell                 {last.row_dwell_us} us")
    print(f"uptime                    {last.uptime_s:.1f} s")
    print(f"scans since boot          {last.scan_count:,}")
    print(f"commands ok / rejected    {last.cmd_ok} / {last.cmd_err}")

    # Sanity checks on the numbers themselves, not just on whether bytes moved.
    problems = []
    if observed_hz < 5.0:
        problems.append(f"telemetry arriving at only {observed_hz:.1f} Hz, expected ~10")
    if last.refresh_hz <= 0:
        problems.append("firmware reports a zero refresh rate: is the scan loop paused?")
    if not 5.0 < last.die_temp_c < 90.0:
        problems.append(f"die temperature of {last.die_temp_c:.1f} C is implausible")
    if stats.crc_errors > max(1, stats.frames_ok // 100):
        problems.append(f"{stats.crc_errors} CRC errors: the link is noisy")
    if last.jitter_pp_us > last.period_mean_us:
        problems.append("jitter exceeds the mean period: the scan loop is being starved")

    print()
    if problems:
        for problem in problems:
            print(f"WARN  {problem}")
        return 1
    print("PASS  link is healthy")
    return 0


if __name__ == "__main__":
    sys.exit(main())
