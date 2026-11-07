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

Payloads only grow by **appending** fields, and every size ever sent stays decodable:

- A dashboard reads a newer board: it decodes the fields it knows and ignores the rest.
- A dashboard reads older firmware or an old capture: it picks the largest layout that fits
  and shows the fields added since as `-`.

## Changing the format

Two implementations of one format drift apart unless something forces them to agree. Here
it is a shared file of reference frames,
[`tools/protocol_vectors.txt`](../tools/protocol_vectors.txt), produced by the C++ code and
decoded by the Python tests.

To add a Status field:

1. **`vmoji/telemetry_frame.h`:** append it to `StatusPayload` and update the size in its
   `static_assert`.
2. **`vmoji/telemetry.cpp`:** fill it in where `status` is built. If the value comes from
   elsewhere, add a setter like `telemetry_set_pov()`.
3. **[`tools/protocol_selftest.cpp`](../tools/protocol_selftest.cpp):** set it in the sample,
   then regenerate the vectors with `tools/update-protocol-vectors.sh`.
4. **`tools/dashboard/protocol.py`:** add a **new entry** to `_STATUS_LAYOUTS`. Never edit an
   existing one: firmware and captures with that size exist forever. Add the field to `Status`
   with a `None` default, and to `pack_status_payload`.
5. **`tools/dashboard/sources.py`:** send a realistic value from `SimSource`.
6. **`tools/dashboard/tests/test_protocol.py`:** add the expected value to `CPP_STATUS_FIELDS`,
   add the new size to `SHIPPED_STATUS_SIZES`, and copy the new `status` vector into
   `FROZEN_STATUS_FRAMES` (never regenerate the existing ones).
7. **Show it:** see [Adding a readout or plot](dashboard.md#adding-a-readout-or-plot).

Then run `scripts/check.sh`. It catches a missed step 1, 3, 4 or 6, and a shipped layout that
was edited. **It can't catch steps 2 and 5:** a field nobody fills in sends zero, and the
simulator sends zero too. So after flashing, check the real value on a board.
