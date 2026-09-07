// Dual-core POV runtime: core 0 signals revolutions; core 1 owns the scanner.

#ifndef VMOJI_POV_RUNTIME_H
#define VMOJI_POV_RUNTIME_H

#include <stdbool.h>
#include <stdint.h>

#include "app_mode.h"
#include "rotation_sync.h"
#include "volume.h"

#ifdef __cplusplus
extern "C" {
#endif

void pov_runtime_init(void);

/** Launch core 1 scanner loop. Call once after init. */
void pov_runtime_start_core1(void);

void pov_runtime_set_mode(AppMode mode);
AppMode pov_runtime_mode(void);

void pov_runtime_set_volume(int volume_id);
int pov_runtime_volume_id(void);

/**
 * Core 0 tick: service sync, bake/flip volumes, signal core 1 on each rev.
 * In static mode this is a no-op for POV (caller runs static scan).
 */
void pov_runtime_service(void);

/** Latest rotation snapshot for telemetry / commands. */
RotationSnapshot pov_runtime_rotation(void);

/** True while core 1 should be blanking after sync loss. */
bool pov_runtime_display_active(void);

/**
 * Publish a freshly baked scanlist for core 1 (DMA copy into shared slot).
 * Called internally; exposed for tests.
 */
void pov_runtime_request_rebake(void);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_POV_RUNTIME_H
