#include "scan_timing.h"

uint32_t scan_timing_step_us(uint32_t period_us, uint32_t step_count)
{
    if (step_count == 0 || period_us == 0) {
        return 1;
    }
    uint32_t step_us = period_us / step_count;
    return step_us == 0 ? 1u : step_us;
}

uint32_t scan_timing_lit_delay_cycles(uint32_t step_us, uint32_t settle_us,
                                      uint32_t sys_hz)
{
    if (settle_us >= step_us) {
        /* Settle ate the whole step; keep a minimal lit pulse. */
        return 1u;
    }
    return scan_timing_delay_cycles(step_us - settle_us, sys_hz);
}

uint32_t scan_timing_delay_cycles(uint32_t step_us, uint32_t sys_hz)
{
    if (step_us == 0) {
        return 1u;
    }
    uint32_t delay_cycles =
        (uint32_t)((uint64_t)step_us * (uint64_t)sys_hz / 1000000ull);
    if (delay_cycles > 32u) {
        delay_cycles -= 32u;
    } else {
        delay_cycles = 1u;
    }
    return delay_cycles;
}
