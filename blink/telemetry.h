// C-callable interface to the telemetry emitter.
//
// The implementation (telemetry.cpp) is C++17 so it can share telemetry_frame.h
// with the host tooling. This header is plain C with an extern "C" block, so
// blink.c can call it without the name mangling that would otherwise make the
// symbols unresolvable at link time.

#ifndef VMOJI_TELEMETRY_H
#define VMOJI_TELEMETRY_H

#include "telemetry_flags.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Initialise counters and the on-die temperature sensor. Call once at boot. */
void telemetry_init(void);

/**
 * Mark the completion of one matrix scan. Measures the interval since the
 * previous call, which is what makes the reported jitter a real observation of
 * the scan loop rather than a nominal figure.
 */
void telemetry_note_scan(void);

/** Account for bytes arriving on either link. */
void telemetry_note_rx_bytes(uint32_t count);

/** Account for one host command, accepted or rejected. */
void telemetry_note_command(bool accepted);

/** Record which glyph is currently displayed (0 if driven directly). */
void telemetry_set_glyph(uint8_t glyph_id);

/** Per-row lit time used by the scan loop. Reported so the host can correlate
 *  a dwell change with the resulting refresh rate. */
void telemetry_set_row_dwell(uint16_t microseconds);
uint16_t telemetry_row_dwell(void);

/** Set or clear a StatusFlag bit (see telemetry_frame.h). */
void telemetry_set_flag(uint8_t flag, bool on);

/** Snapshot the 8x8 framebuffer for the next FrameBuffer message.
 *  Expects the base address of a bool[8][8]. */
void telemetry_set_framebuffer(const bool *framebuffer);

/** Reset the interval and lifetime counters. */
void telemetry_reset_counters(void);

/**
 * Emit due messages. Call from the main loop; it is non-blocking apart from the
 * serial write itself and sends nothing until a reporting interval has elapsed.
 */
void telemetry_service(void);

/** Send a human-readable line as a Log message. */
void telemetry_log(const char *text);

/** Send a command acknowledgement. */
void telemetry_ack(const char *text);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_TELEMETRY_H
