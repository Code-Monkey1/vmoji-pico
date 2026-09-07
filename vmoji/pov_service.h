// Core-0 POV service FSM, injectable for host tests.
//
// Multicore / PIO live in pov_runtime.c behind PovPlatform hooks.

#ifndef VMOJI_POV_SERVICE_H
#define VMOJI_POV_SERVICE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "app_mode.h"
#include "rotation_sync.h"
#include "volume.h"
#include "volume_codec.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    void (*copy)(void *dst, const void *src, size_t n);
    void (*blank)(void);
    /** Publish a stable scanlist pointer for core1; must outlive the rev. */
    void (*signal_start)(uint32_t period_us, const VolumeScanlist *list);
    void (*signal_stop)(void);
    void (*note_scan)(void);
    void (*sync_reset)(void);
    void (*sync_set_sim)(bool enabled);
    void (*sync_service)(void);
    bool (*sync_take_rev)(RotationSnapshot *out);
    /** Edge-triggered: true once after IR lock timeout. */
    bool (*sync_take_lost)(void);
    RotationSnapshot (*sync_snapshot)(void);
} PovPlatform;

typedef struct {
    VolumeBuffer volume;
    VolumeScanlist lists[2];
    uint8_t display_list;   /* latest complete bake */
    uint8_t busy_slot;      /* slot core1 may be reading */
    bool scan_busy;
    bool rebake_needed;
    bool display_active;
    bool core_stop;
    AppMode mode;
    int volume_id;
    RotationSnapshot last_rot;
    const PovPlatform *plat;
} PovService;

void pov_service_init(PovService *svc, const PovPlatform *plat);

void pov_service_set_mode(PovService *svc, AppMode mode);
AppMode pov_service_mode(const PovService *svc);

void pov_service_set_volume(PovService *svc, int volume_id);
int pov_service_volume_id(const PovService *svc);

void pov_service_request_rebake(PovService *svc);

/** Core-0 tick: sync, bake, signal start or blank on sync loss. */
void pov_service_service(PovService *svc);

/**
 * Core1 finished or aborted a rev — free busy_slot for the next bake.
 * Safe to call from core1.
 */
void pov_service_release_scan(PovService *svc);

RotationSnapshot pov_service_rotation(const PovService *svc);
bool pov_service_display_active(const PovService *svc);
uint8_t pov_service_display_list(const PovService *svc);
uint8_t pov_service_busy_slot(const PovService *svc);
bool pov_service_scan_busy(const PovService *svc);
const VolumeScanlist *pov_service_list(const PovService *svc, uint8_t index);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_POV_SERVICE_H
