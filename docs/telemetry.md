# Telemetry

The firmware streams binary telemetry on USB and UART0 at the same time. The format is
defined once in C++ ([`vmoji/telemetry_frame.h`](../vmoji/telemetry_frame.h)) and
re-implemented in Python for the dashboard
([`tools/dashboard/protocol.py`](../tools/dashboard/protocol.py)).

## Links

| Link | Device | Settings |
|------|--------|----------|
| USB CDC | `/dev/ttyACM0` | Any baud rate (ignored on USB) |
| UART0 | GP0 TX, GP1 RX | 115200 8N1 (`UART_LINK_BAUD`) |

UART output starts with a short plain-text banner (it lists the command letters). USB drops
everything sent before a host opens the port, so a dashboard joining later starts
mid-stream. The parser simply finds the next frame.

## Frames

```
offset  size  field
0       2     sync word 0xAA 0x55
2       2     payload length, little-endian
4       1     message id
5       1     sequence number (wraps at 256)
6       N     payload
6+N     2     CRC-16/CCITT-FALSE over bytes [2, 6+N)
```

- The **sync word** lets a reader lock onto a stream it joined mid-frame.
- The **length** lets the payload hold any bytes, with no escaping.
- The **sequence number** makes lost frames visible as gaps.
- The **CRC** drops corrupted frames instead of plotting them. It skips the sync word, so a
  sync word that happens to appear inside a payload can't produce a frame that also passes
  the CRC.

## Messages

| Id | Message | Rate | Content |
|----|---------|------|---------|
| `0x01` | Status | 10 Hz | Health and timing: scan rate and period, jitter, die temperature, command counts, mode, rotor speed, flags |
| `0x02` | FrameBuffer | 2 Hz | The 8×8 image currently shown |
| `0x03` | Log | On event | ASCII text, including an `ID vmoji …` line every 10 s and on `I` |
| `0x10` | Ack | Per command | The ASCII reply to a command ([Commands](commands.md)) |

The fields of `StatusPayload` and the status flags are documented where they are defined:
[`telemetry_frame.h`](../vmoji/telemetry_frame.h) and
[`telemetry_flags.h`](../vmoji/telemetry_flags.h). Flags that signal lost data (`OVERRUN`,
`TX_DROP`, `FIFO_OVF`) are highlighted by the dashboard.

## Never blocking the scan

Telemetry measures the scan loop, so it must not disturb it. Frames go into per-link ring
buffers that drain in the background; a frame that doesn't fit is dropped whole and raises
the `TX_DROP` flag. An early version wrote frames with blocking calls and was the largest
source of the jitter it reported. The design notes are at the top of
[`telemetry.cpp`](../vmoji/telemetry.cpp).

## Compatibility

Payloads only grow by **appending** fields. A reader decodes the fields it knows and
ignores the rest, so an older dashboard keeps working with newer firmware. The dashboard
also still reads the original 32-byte Status from older firmware and captures, and shows
the newer fields as `-`.

## Changing the format

Two implementations of one format drift apart unless something forces them to agree. Here
it is a shared file of reference frames,
[`tools/protocol_vectors.txt`](../tools/protocol_vectors.txt), produced by the C++ code and
decoded by the Python tests.

1. Change the C++ side: `telemetry_frame.h`, and the sample values in
   [`tools/protocol_selftest.cpp`](../tools/protocol_selftest.cpp).
2. Regenerate the vectors: `tools/update-protocol-vectors.sh`.
3. Update `protocol.py` (and the expected values in `tests/test_protocol.py`) until
   `scripts/check.sh` passes.

If you skip a step, a test fails: the `protocol_vectors_current` ctest catches stale
vectors, and the Python tests catch a decoder that no longer reads the whole payload.
