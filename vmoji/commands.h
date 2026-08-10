// Host command handling: line assembly and dispatch.
//
// Commands stay ASCII and line-oriented on purpose: during bring-up you want to
// drive the board from minicom with no tooling at all. Only the high-rate
// telemetry going the other way is binary, where framing and a CRC earn their
// keep.
//
//   S <0-9> <0-9>   set the two score digits
//   H               heartbeat, pulses the activity pixel
//   G <0-5>         select a glyph
//   D <us>          set per-row dwell time
//   B               blank the display
//   P               toggle scan pause
//   Z               reset counters
//   ?               report the current configuration
//   I               report firmware version and unique board id

#ifndef VMOJI_COMMANDS_H
#define VMOJI_COMMANDS_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** The dwell range accepted by `D`. Mirrored by the host in protocol.py. */
#define DWELL_MIN_US 50
#define DWELL_MAX_US 5000

/**
 * Feed one received byte, from either link.
 *
 * Assembles a line and dispatches it on newline. Single consumer: both the UART
 * ring and USB stdio are drained by the main loop, never concurrently.
 */
void commands_feed_byte(uint8_t ch);

/** True while the host has paused scanning with `P`. */
bool commands_scan_paused(void);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_COMMANDS_H
