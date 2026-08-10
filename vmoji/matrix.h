// The display: pin mapping, the multiplexed scan, and what is drawn on it.
//
// Everything that knows the matrix is 8x8 and which GPIO drives which line
// lives behind this interface. Callers ask for a glyph or a score and never
// touch a pin, which is what lets the scan timing be reasoned about in one
// place - it is the real-time part of the firmware, and the only one.

#ifndef VMOJI_MATRIX_H
#define VMOJI_MATRIX_H

#include <stdbool.h>
#include <stdint.h>

#include "led-matrix.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Number of glyphs selectable with the `G <id>` command. */
#define GLYPH_COUNT 6

/** Configure the GPIOs and blank the display. Call once at boot. */
void matrix_init(void);

/** Drive all rows and columns off. */
void matrix_blank(void);

/**
 * Scan the framebuffer out once, one row at a time.
 *
 * This is the timed operation the whole telemetry system exists to measure, so
 * it must not acquire locks or perform I/O beyond the GPIO writes themselves.
 */
void matrix_refresh(void);

/** The base address of the bool[8][8] framebuffer, for telemetry snapshots. */
const bool *matrix_framebuffer(void);

/** Per-row lit time. Longer is brighter and slower; the host trades the two. */
void matrix_set_row_dwell(uint16_t microseconds);

/** The dwell currently in effect, for reporting it back to the host. */
uint16_t matrix_row_dwell(void);

void matrix_clear(void);

/** Draw one of the built-in glyphs. Ignores an out-of-range id. */
void matrix_draw_glyph(int glyph_id);

/** Draw two single digits, home on the left and away on the right. */
void matrix_draw_score(int home, int away);

/**
 * Light the activity pixel for a while.
 *
 * ``extend`` only ever pushes the deadline later, so a burst of score updates
 * reads as one continuous blink; without it, a pulse restarts each time and the
 * pixel appears to stutter.
 */
void matrix_arm_activity(uint32_t duration_us, bool extend);

/** True while the activity pixel is still being blinked. */
bool matrix_activity_pending(void);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_MATRIX_H
