// Pure scan pacing math — shared by pio_scan.c and host tests.

#ifndef VMOJI_SCAN_TIMING_H
#define VMOJI_SCAN_TIMING_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Microseconds per equal-timed step for one revolution. At least 1. */
uint32_t scan_timing_step_us(uint32_t period_us, uint32_t step_count);

/**
 * Lit-time PIO delay cycles after reserving settle_us for blanking.
 * Always at least 1. If step_us <= settle_us, returns 1 (slight over-period).
 */
uint32_t scan_timing_lit_delay_cycles(uint32_t step_us, uint32_t settle_us,
                                      uint32_t sys_hz);

/**
 * PIO delay cycles for a step at sys_hz, after a small overhead subtract.
 * Always at least 1. (settle_us = 0)
 */
uint32_t scan_timing_delay_cycles(uint32_t step_us, uint32_t sys_hz);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_SCAN_TIMING_H
