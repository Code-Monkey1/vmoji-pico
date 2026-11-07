// Once-per-rev phase lock: IR GPIO IRQ, period EMA, and a sim ticker.

#ifndef VMOJI_ROTATION_SYNC_H
#define VMOJI_ROTATION_SYNC_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Nominal sim rate used when no IR sensor is attached. */
#define ROTATION_SIM_RPM 1000u
#define ROTATION_SIM_PERIOD_US (60000000u / ROTATION_SIM_RPM)

typedef struct {
    uint32_t period_us;
    uint32_t rev_count;
    uint16_t rpm;
    bool sync_ok;
    bool sim;
} RotationSnapshot;

void rotation_sync_init(void);

/** Enable IR edge IRQ (pov) or software ticker (sim). */
void rotation_sync_set_sim(bool enabled);

/** Poll from core 0: services sim ticks and latches IRQ edges. */
void rotation_sync_service(void);

/**
 * True once per new revolution index pulse (IR or sim).
 * Writes the latest snapshot when returning true.
 */
bool rotation_sync_take_rev(RotationSnapshot *out);

/**
 * True once when IR lock is lost (no edge for ROT_EST_SYNC_LOSS_US).
 * Cleared when read. Never fires in sim mode.
 */
bool rotation_sync_take_sync_lost(void);

RotationSnapshot rotation_sync_snapshot(void);

/** Force period estimate (e.g. after mode change). */
void rotation_sync_reset(void);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_ROTATION_SYNC_H
