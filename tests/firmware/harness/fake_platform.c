#include "fake_platform.h"

#include "fake_time.h"
#include "rotation_sync.h"

#include <string.h>

static FakePlatformState *g_st;

static void fake_copy(void *dst, const void *src, size_t n)
{
    memcpy(dst, src, n);
}

static void fake_blank(void)
{
    g_st->blank_count++;
}

static void fake_signal_start(uint32_t period_us, const VolumeScanlist *list)
{
    g_st->start_count++;
    g_st->last_period_us = period_us;
    g_st->last_list = list;
}

static void fake_signal_stop(void)
{
    g_st->stop_count++;
}

static void fake_note_scan(void)
{
    g_st->note_scan_count++;
}

static void fake_sync_reset(void)
{
    g_st->pending_rev = false;
    g_st->edge_pending = false;
    g_st->sync_lost_pending = false;
    if (g_st->use_estimator) {
        rotation_estimator_reset(&g_st->est, ROTATION_SIM_PERIOD_US);
    }
}

static void fake_sync_set_sim(bool enabled)
{
    g_st->sim = enabled;
    if (g_st->use_estimator) {
        rotation_estimator_set_sim(&g_st->est, enabled, ROTATION_SIM_PERIOD_US);
    }
    g_st->edge_pending = false;
    g_st->sync_lost_pending = false;
}

static void fake_sync_service(void) {}

static bool fake_sync_take_rev(RotationSnapshot *out)
{
    if (g_st->use_estimator) {
        if (!g_st->edge_pending) {
            if (rotation_estimator_check_loss(&g_st->est, fake_time_now_us())) {
                g_st->sync_lost_pending = true;
            }
            return false;
        }
        g_st->edge_pending = false;
        rotation_estimator_note_edge(&g_st->est, g_st->edge_us);
        g_st->sync_lost_pending = false;
        g_st->snapshot = rotation_estimator_snapshot(&g_st->est);
        if (out) {
            *out = g_st->snapshot;
        }
        return true;
    }

    if (!g_st->pending_rev) {
        return false;
    }
    g_st->pending_rev = false;
    if (out) {
        *out = g_st->pending_snap;
    }
    g_st->snapshot = g_st->pending_snap;
    return true;
}

static bool fake_sync_take_lost(void)
{
    if (g_st->use_estimator) {
        if (!g_st->sync_lost_pending && !g_st->edge_pending) {
            if (rotation_estimator_check_loss(&g_st->est, fake_time_now_us())) {
                g_st->sync_lost_pending = true;
            }
        }
        if (!g_st->sync_lost_pending) {
            return false;
        }
        g_st->sync_lost_pending = false;
        return true;
    }
    return false;
}

static RotationSnapshot fake_sync_snapshot(void)
{
    if (g_st->use_estimator) {
        return rotation_estimator_snapshot(&g_st->est);
    }
    return g_st->snapshot;
}

void fake_platform_reset(FakePlatformState *st)
{
    memset(st, 0, sizeof(*st));
}

PovPlatform fake_platform_make(FakePlatformState *st)
{
    g_st = st;
    PovPlatform p = {
        .copy = fake_copy,
        .blank = fake_blank,
        .signal_start = fake_signal_start,
        .signal_stop = fake_signal_stop,
        .note_scan = fake_note_scan,
        .sync_reset = fake_sync_reset,
        .sync_set_sim = fake_sync_set_sim,
        .sync_service = fake_sync_service,
        .sync_take_rev = fake_sync_take_rev,
        .sync_take_lost = fake_sync_take_lost,
        .sync_snapshot = fake_sync_snapshot,
    };
    return p;
}

void fake_platform_push_rev(FakePlatformState *st, const RotationSnapshot *snap)
{
    st->pending_snap = *snap;
    st->pending_rev = true;
}

void fake_platform_use_estimator(FakePlatformState *st, bool enable)
{
    st->use_estimator = enable;
    if (enable) {
        rotation_estimator_init(&st->est, ROTATION_SIM_PERIOD_US);
    }
}

void fake_platform_push_edge(FakePlatformState *st, uint64_t now_us)
{
    st->edge_us = now_us;
    st->edge_pending = true;
}
