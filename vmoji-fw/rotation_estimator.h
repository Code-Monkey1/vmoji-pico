// Pure rotation period estimator — no GPIO or IRQ.
//
// rotation_sync.c wraps this with IR edges / sim ticks and a wall clock.

#ifndef VMOJI_ROTATION_ESTIMATOR_H
#define VMOJI_ROTATION_ESTIMATOR_H

#include <stdbool.h>
#include <stdint.h>

#include "rotation_sync.h"

#ifdef __cplusplus
extern "C" {
#endif

#define ROT_EST_EMA_NUM 3u
#define ROT_EST_EMA_DEN 4u
#define ROT_EST_MIN_PERIOD_US 5000u
#define ROT_EST_MAX_PERIOD_US 500000u
#define ROT_EST_SYNC_LOSS_US 250000u

typedef struct {
    uint64_t last_edge_us;
    uint32_t period_us;
    uint32_t rev_count;
    bool sync_ok;
    bool sim;
} RotationEstimator;

void rotation_estimator_init(RotationEstimator *e, uint32_t default_period_us);

void rotation_estimator_reset(RotationEstimator *e, uint32_t default_period_us);

void rotation_estimator_set_sim(RotationEstimator *e, bool sim,
                               uint32_t default_period_us);

/** Record an index edge at now_us. Updates EMA when the sample is in range. */
void rotation_estimator_note_edge(RotationEstimator *e, uint64_t now_us);

/**
 * If sync was ok and now_us is past the loss window since last edge, clear
 * sync_ok. Returns true if sync was just lost.
 */
bool rotation_estimator_check_loss(RotationEstimator *e, uint64_t now_us);

uint16_t rotation_estimator_rpm(const RotationEstimator *e);

RotationSnapshot rotation_estimator_snapshot(const RotationEstimator *e);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_ROTATION_ESTIMATOR_H
