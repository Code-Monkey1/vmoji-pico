#include "rotation_estimator.h"

uint16_t rotation_estimator_rpm(const RotationEstimator *e)
{
    if (e->period_us == 0) {
        return 0;
    }
    uint32_t rpm = 60000000u / e->period_us;
    return rpm > 0xFFFFu ? 0xFFFFu : (uint16_t)rpm;
}

void rotation_estimator_init(RotationEstimator *e, uint32_t default_period_us)
{
    e->last_edge_us = 0;
    e->period_us = default_period_us;
    e->rev_count = 0;
    e->sync_ok = false;
    e->sim = false;
}

void rotation_estimator_reset(RotationEstimator *e, uint32_t default_period_us)
{
    e->last_edge_us = 0;
    e->period_us = default_period_us;
    e->sync_ok = false;
    /* rev_count preserved across reset so hosts can see activity */
}

void rotation_estimator_set_sim(RotationEstimator *e, bool sim,
                               uint32_t default_period_us)
{
    e->sim = sim;
    e->sync_ok = false;
    e->last_edge_us = 0;
    if (sim) {
        e->period_us = default_period_us;
    }
}

void rotation_estimator_note_edge(RotationEstimator *e, uint64_t now_us)
{
    if (e->last_edge_us != 0) {
        uint32_t sample = (uint32_t)(now_us - e->last_edge_us);
        if (sample >= ROT_EST_MIN_PERIOD_US && sample <= ROT_EST_MAX_PERIOD_US) {
            if (e->period_us == 0) {
                e->period_us = sample;
            } else {
                e->period_us =
                    (e->period_us * ROT_EST_EMA_NUM + sample) / ROT_EST_EMA_DEN;
            }
        }
    }
    e->last_edge_us = now_us;
    e->rev_count++;
    e->sync_ok = true;
}

bool rotation_estimator_check_loss(RotationEstimator *e, uint64_t now_us)
{
    if (!e->sync_ok || e->sim) {
        return false;
    }
    if (e->last_edge_us != 0 &&
        (now_us - e->last_edge_us) > ROT_EST_SYNC_LOSS_US) {
        e->sync_ok = false;
        return true;
    }
    return false;
}

RotationSnapshot rotation_estimator_snapshot(const RotationEstimator *e)
{
    RotationSnapshot s;
    s.period_us = e->period_us;
    s.rev_count = e->rev_count;
    s.rpm = rotation_estimator_rpm(e);
    s.sync_ok = e->sync_ok || e->sim;
    s.sim = e->sim;
    return s;
}
