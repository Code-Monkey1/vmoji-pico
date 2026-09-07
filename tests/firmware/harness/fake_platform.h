#ifndef VMOJI_FAKE_PLATFORM_H
#define VMOJI_FAKE_PLATFORM_H

#include "pov_service.h"
#include "rotation_estimator.h"

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    int blank_count;
    int start_count;
    int stop_count;
    int note_scan_count;
    uint32_t last_period_us;
    const VolumeScanlist *last_list;

    bool pending_rev;
    RotationSnapshot pending_snap;

    bool use_estimator;
    RotationEstimator est;
    bool edge_pending;
    uint64_t edge_us;
    bool sync_lost_pending;
    bool sim;

    RotationSnapshot snapshot;
} FakePlatformState;

void fake_platform_reset(FakePlatformState *st);
PovPlatform fake_platform_make(FakePlatformState *st);

void fake_platform_push_rev(FakePlatformState *st, const RotationSnapshot *snap);
void fake_platform_use_estimator(FakePlatformState *st, bool enable);
void fake_platform_push_edge(FakePlatformState *st, uint64_t now_us);

#endif
