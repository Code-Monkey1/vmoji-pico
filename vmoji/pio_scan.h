// Matrix scanner: parallel GPIO masks paced by a PIO delay SM.
//
// Pin map is non-contiguous, so masks are applied with gpio_put_masked (one
// SIO write to the relevant bits). PIO provides cycle-accurate dwell; DMA can
// prime the delay FIFO for a revolution.

#ifndef VMOJI_PIO_SCAN_H
#define VMOJI_PIO_SCAN_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "volume_codec.h"

#ifdef __cplusplus
extern "C" {
#endif

void pio_scan_init(void);

/** Drive every matrix LED off. Safe from either core before POV starts. */
void pio_scan_blank(void);

/** Word-aligned DMA memcpy (scanlist publish between cores). */
void pio_scan_dma_copy(void *dst, const void *src, size_t bytes);

/**
 * Display one revolution of pre-baked steps.
 * period_us is the measured (or simulated) revolution time.
 * abort_check is polled between steps; may be NULL.
 * Returns false if aborted early.
 */
bool pio_scan_run_rev(const VolumeScanlist *list, uint32_t period_us,
                      bool (*abort_check)(void));

/**
 * Static bring-up: scan row masks once with a fixed dwell (microseconds).
 * Used when operating mode is `static`.
 */
void pio_scan_static_frame(const uint32_t row_words[8], uint32_t blank,
                           uint32_t pin_mask, uint16_t dwell_us);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_PIO_SCAN_H
