#!/usr/bin/env python3
"""
Poll the NHL web scoreboard for the Montreal Canadiens (MTL) and send score updates to the
Pico 8x8 firmware over UART.

Protocol (115200 8N1, line-terminated with \\n or \\r\\n)::

    S <mtl_goals> <opp_goals>
    H

``S`` sets the score digits. ``H`` (heartbeat) is sent after each NHL poll and, during long sleeps, at least every
``--uart-heartbeat-interval`` seconds so the activity LED blinks periodically even when
``--slow-poll`` is large (``--fast-poll`` only applies to LIVE/CRIT/PRE games).

Digits must be 0-9 (firmware display limit). First number is always MTL; second is the opponent.

Serial device (Linux):

- **Pico USB** (``/dev/ttyACM0``): the firmware reads score lines on **USB CDC** as well as on
  **UART0** (GP1). Use this if the PC only connects by USB (no separate TTL adapter).
- **USB–TTL on GP0/GP1**: use ``/dev/ttyUSB*`` (or ``by-id``). **PC TX → Pico GP1 (RX)**,
  **GND** common; 115200 8N1.

If you use minicom on ``ttyACM0`` you must flash firmware that reads from USB (this project does).
Lines like ``S 2 3`` sent by the Python script then update the matrix; you should see ``OK 2-3`` back
on the same port when a line is accepted.

The script waits briefly after opening the serial port and after each write, and drains pending RX
bytes, so the first command is not merged with boot noise. ``--agent-debug-log`` only adds NDJSON
lines to ``.cursor/debug-9c520a.log`` for troubleshooting; it does not change score behaviour.

Dependencies: see requirements.txt (``pip install -r requirements.txt``).
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
import time
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Iterator

SCORE_URL = "https://api-web.nhle.com/v1/score/{date}"

# Prefer faster polling when the game is underway or about to start.
FAST_POLL_STATES = frozenset({"LIVE", "CRIT", "PRE"})

LOG = logging.getLogger("habs_score_uart")

# #region agent log
_AGENT_LOG_PATH = Path("/home/gordo/Documents/Projects/VolumetricDisplay/.cursor/debug-9c520a.log")
_AGENT_SESSION = "9c520a"


def agent_log(hypothesis_id: str, location: str, message: str, data: dict[str, Any] | None = None) -> None:
    entry = {
        "sessionId": _AGENT_SESSION,
        "hypothesisId": hypothesis_id,
        "location": location,
        "message": message,
        "timestamp": int(time.time() * 1000),
        "data": data or {},
    }
    _AGENT_LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    with _AGENT_LOG_PATH.open("a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def serial_prepare_after_open(ser: Any) -> None:
    """Avoid framing a command into the same line as boot noise; drain stale RX."""
    try:
        ser.dtr = False
    except (AttributeError, OSError, ValueError):
        pass
    try:
        ser.rts = False
    except (AttributeError, OSError, ValueError):
        pass
    time.sleep(0.4)
    try:
        ser.reset_input_buffer()
    except (AttributeError, OSError, ValueError):
        pass


def serial_send_heartbeat(ser: Any, *, agent_debug: bool) -> None:
    """Tell the Pico a poll cycle completed (blinks activity pixel); does not change the score."""
    payload = b"H\n"
    if agent_debug:
        agent_log(
            "H2",
            "habs_score_uart:serial_send_heartbeat",
            "pre_write",
            {"in_waiting": ser.in_waiting, "out_repr": "H<LF>"},
        )
    ser.write(payload)
    ser.flush()
    old_timeout = ser.timeout
    try:
        time.sleep(0.02)
        ser.timeout = 0
        drained = ser.read(512)
    finally:
        ser.timeout = old_timeout
    if agent_debug:
        agent_log(
            "H3",
            "habs_score_uart:serial_send_heartbeat",
            "post_write_read",
            {"rx_len": len(drained), "rx_hex": drained.hex()},
        )


def serial_send_score_payload(ser: Any, payload: bytes, *, label: str, agent_debug: bool) -> None:
    """Write ``S h a\\n``, wait briefly, drain RX (echo/OK) so the link stays deterministic."""
    if agent_debug:
        agent_log(
            "H2",
            "habs_score_uart:serial_send_score_payload",
            "pre_write",
            {
                "label": label,
                "port": getattr(ser, "port", None),
                "baudrate": getattr(ser, "baudrate", None),
                "in_waiting": ser.in_waiting,
                "out_len": len(payload),
                "out_repr": payload.decode("ascii", errors="replace"),
            },
        )
    ser.write(payload)
    ser.flush()
    old_timeout = ser.timeout
    try:
        time.sleep(0.06)
        ser.timeout = 0
        drained = ser.read(4096)
    finally:
        ser.timeout = old_timeout
    if agent_debug:
        agent_log(
            "H3",
            "habs_score_uart:serial_send_score_payload",
            "post_write_read",
            {
                "label": label,
                "rx_len": len(drained),
                "rx_hex": drained.hex(),
                "rx_repr": drained.decode("ascii", errors="replace"),
            },
        )


def sleep_between_polls(ser: Any, sleep_for: float, uart_hb_interval: float, agent_debug: bool) -> None:
    """Send poll-done ``H``, then sleep ``sleep_for`` s with extra ``H`` every ``uart_hb_interval`` when sleep is long."""
    serial_send_heartbeat(ser, agent_debug=agent_debug)
    remaining = float(sleep_for)
    while remaining > 1e-6:
        chunk = min(remaining, uart_hb_interval)
        time.sleep(chunk)
        remaining -= chunk
        if remaining > 1e-6:
            LOG.debug("UART heartbeat during poll sleep (%.1fs remaining)", remaining)
            serial_send_heartbeat(ser, agent_debug=agent_debug)


# #endregion


@dataclass(frozen=True)
class MtlGame:
    mtl: int
    opp: int
    game_state: str


def clamp_goal(n: Any, label: str) -> int | None:
    if n is None:
        return None
    try:
        v = int(n)
    except (TypeError, ValueError):
        LOG.warning("Non-integer %s score %r; skipping game row", label, n)
        return None
    if v < 0:
        return 0
    if v > 9:
        LOG.warning("%s score %s exceeds 9; clamping for UART display", label, v)
        return 9
    return v


def extract_mtl_from_scoreboard(data: dict[str, Any]) -> MtlGame | None:
    """Pick a single MTL game from a /v1/score/{date} JSON object (newest / most relevant first)."""
    games = data.get("games")
    if not isinstance(games, list):
        return None

    candidates: list[MtlGame] = []
    for g in games:
        if not isinstance(g, dict):
            continue
        ht = g.get("homeTeam") or {}
        at = g.get("awayTeam") or {}
        if not isinstance(ht, dict) or not isinstance(at, dict):
            continue
        ha = str(ht.get("abbrev", "")).upper()
        aa = str(at.get("abbrev", "")).upper()
        state = str(g.get("gameState", "") or "")
        if ha == "MTL":
            mtl = clamp_goal(ht.get("score"), "MTL")
            opp = clamp_goal(at.get("score"), "OPP")
        elif aa == "MTL":
            mtl = clamp_goal(at.get("score"), "MTL")
            opp = clamp_goal(ht.get("score"), "OPP")
        else:
            continue
        if mtl is None or opp is None:
            continue
        candidates.append(MtlGame(mtl=mtl, opp=opp, game_state=state))

    if not candidates:
        return None

    def sort_key(c: MtlGame) -> tuple[int, str]:
        # Prefer in-progress games; then CRIT/LIVE; then others. Stable on state string.
        live_rank = 0 if c.game_state in FAST_POLL_STATES else 1
        return (live_rank, c.game_state)

    candidates.sort(key=sort_key)
    return candidates[0]


def local_iso_dates() -> Iterator[str]:
    """Today then yesterday in the local timezone (for late-night / API date edges)."""
    local = datetime.now().astimezone()
    today: date = local.date()
    yield today.isoformat()
    yield (today - timedelta(days=1)).isoformat()


def load_state(path: Path) -> tuple[int, int] | None:
    if not path.is_file():
        return None
    try:
        raw = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        LOG.warning("Could not read state file %s: %s", path, e)
        return None
    if not isinstance(raw, dict):
        return None
    try:
        h = int(raw["h"])
        a = int(raw["a"])
    except (KeyError, TypeError, ValueError):
        return None
    if 0 <= h <= 9 and 0 <= a <= 9:
        return h, a
    return None


def save_state(path: Path, h: int, a: int) -> None:
    path.write_text(json.dumps({"h": h, "a": a}, indent=2) + "\n", encoding="utf-8")


def format_score_line(h: int, a: int) -> bytes:
    return f"S {h} {a}\n".encode("ascii")


def fetch_scoreboard(session: Any, day: str) -> dict[str, Any]:
    url = SCORE_URL.format(date=day)
    r = session.get(url, timeout=30)
    r.raise_for_status()
    out = r.json()
    if not isinstance(out, dict):
        raise ValueError("scoreboard JSON root is not an object")
    return out


def run_self_test() -> None:
    fixture = Path(__file__).resolve().parent / "fixtures" / "scoreboard_sample.json"
    data = json.loads(fixture.read_text(encoding="utf-8"))
    g = extract_mtl_from_scoreboard(data)
    assert g is not None
    # LIVE BOS-MTL should win sort over OFF MTL home
    assert g.mtl == 3 and g.opp == 1 and g.game_state == "LIVE"
    g2 = extract_mtl_from_scoreboard({"games": [data["games"][0]]})
    assert g2 is not None and g2.mtl == 5 and g2.opp == 2
    print("self-test ok", file=sys.stderr)


def main() -> int:
    default_state = Path(__file__).resolve().parent / "last_score.json"
    parser = argparse.ArgumentParser(
        description="Poll NHL scores for MTL and send UART lines to the Pico (S h a).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--port",
        default=None,
        help="Serial device (e.g. /dev/ttyUSB0, /dev/ttyACM0, or /dev/serial/by-id/...). Required unless --self-test.",
    )
    parser.add_argument("--baud", type=int, default=115200, help="UART baud rate.")
    parser.add_argument("--fast-poll", type=float, default=12.0, help="Seconds between NHL polls during LIVE/CRIT/PRE.")
    parser.add_argument("--slow-poll", type=float, default=180.0, help="Seconds between NHL polls when idle or game over.")
    parser.add_argument(
        "--uart-heartbeat-interval",
        type=float,
        default=15.0,
        metavar="SEC",
        help="Minimum seconds between UART H heartbeats while waiting for the next NHL poll (keeps LED blinking during long slow_poll).",
    )
    parser.add_argument("--state-file", type=Path, default=default_state, help="Persist last sent h,a JSON here.")
    parser.add_argument("--self-test", action="store_true", help="Load fixture and exit (no serial, no network).")
    parser.add_argument(
        "--agent-debug-log",
        action="store_true",
        help="Append NDJSON serial TX/RX traces to .cursor/debug-9c520a.log (optional; score path unchanged).",
    )
    parser.add_argument("-v", "--verbose", action="store_true", help="DEBUG logging.")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )

    if args.self_test:
        run_self_test()
        return 0

    if not args.port:
        parser.error("--port is required (unless using --self-test)")

    import requests
    import serial

    last_sent: tuple[int, int] | None = None

    try:
        ser = serial.Serial(
            args.port,
            baudrate=args.baud,
            timeout=0.5,
            dsrdtr=False,
            rtscts=False,
        )
    except serial.SerialException as e:
        LOG.error("Could not open serial %s: %s", args.port, e)
        # #region agent log
        if args.agent_debug_log:
            agent_log(
                "H1",
                "habs_score_uart:main",
                "serial_open_failed",
                {"port": args.port, "baud": args.baud, "error": str(e)},
            )
        # #endregion
        return 1

    # #region agent log
    if args.agent_debug_log:
        agent_log(
            "H1",
            "habs_score_uart:main",
            "serial_open_ok",
            {"port": args.port, "baud": args.baud},
        )
    # #endregion

    with ser:
        serial_prepare_after_open(ser)

        restored = load_state(args.state_file)
        if restored is not None:
            h, a = restored
            payload = format_score_line(h, a)
            serial_send_score_payload(ser, payload, label="restore", agent_debug=args.agent_debug_log)
            time.sleep(0.22)
            serial_send_score_payload(ser, payload, label="restore_retry", agent_debug=args.agent_debug_log)
            last_sent = restored
            LOG.info("Restored last score from file: MTL %s - %s", h, a)

        session = requests.Session()
        session.headers.update({"User-Agent": "vmoji-pico-habs-score/1.0"})

        try:
            while True:
                sleep_for = args.slow_poll
                info: MtlGame | None = None
                try:
                    for day in local_iso_dates():
                        try:
                            data = fetch_scoreboard(session, day)
                        except (requests.RequestException, ValueError) as e:
                            LOG.warning("Scoreboard fetch failed for %s: %s", day, e)
                            continue
                        info = extract_mtl_from_scoreboard(data)
                        if info is not None:
                            LOG.debug(
                                "Using game from %s: MTL %s - %s (%s)",
                                day,
                                info.mtl,
                                info.opp,
                                info.game_state,
                            )
                            break
                except Exception:
                    LOG.exception("Unexpected error while polling")

                if info is not None:
                    pair = (info.mtl, info.opp)
                    if info.game_state in FAST_POLL_STATES:
                        sleep_for = args.fast_poll
                    if pair != last_sent:
                        serial_send_score_payload(
                            ser,
                            format_score_line(info.mtl, info.opp),
                            label="score_update",
                            agent_debug=args.agent_debug_log,
                        )
                        last_sent = pair
                        try:
                            save_state(args.state_file, info.mtl, info.opp)
                        except OSError as e:
                            LOG.warning("Could not save state file: %s", e)
                        LOG.info("Sent UART: MTL %s - %s (%s)", info.mtl, info.opp, info.game_state or "?")
                else:
                    LOG.info("No MTL game in recent local dates; not sending UART (display unchanged).")

                LOG.debug(
                    "Poll cycle finished; next NHL poll in %.1fs (UART H at least every %.1fs while waiting).",
                    sleep_for,
                    args.uart_heartbeat_interval,
                )
                sleep_between_polls(ser, sleep_for, args.uart_heartbeat_interval, args.agent_debug_log)
        except KeyboardInterrupt:
            LOG.info("Exiting.")
            return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
