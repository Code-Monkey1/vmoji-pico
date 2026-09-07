#include "pov_runtime.h"

#include "core1_cmd.h"
#include "pio_scan.h"
#include "pov_service.h"
#include "rotation_sync.h"
#include "telemetry.h"
#include "telemetry_flags.h"

#include "pico/multicore.h"
#include "pico/stdlib.h"
#include "hardware/sync.h"

#include <string.h>

static PovService g_svc;
static volatile uint32_t g_core1_period_us = ROTATION_SIM_PERIOD_US;
static volatile const VolumeScanlist *g_core1_list_ptr;
static volatile bool g_core1_stop = true;
static volatile bool g_display_active;
static volatile bool g_fifo_overflow;
static bool g_fifo_ovf_logged;

static void fifo_try_push(uint32_t cmd)
{
    if (multicore_fifo_wready()) {
        multicore_fifo_push_blocking(cmd);
        return;
    }
    /* FIFO full: still publish stop via flag; count overflow. */
    g_fifo_overflow = true;
    for (int i = 0; i < 64; i++) {
        if (multicore_fifo_wready()) {
            multicore_fifo_push_blocking(cmd);
            return;
        }
        tight_loop_contents();
    }
}

static void plat_copy(void *dst, const void *src, size_t n)
{
    pio_scan_dma_copy(dst, src, n);
}

static void plat_blank(void)
{
    pio_scan_blank();
}

static void plat_signal_start(uint32_t period_us, const VolumeScanlist *list)
{
    g_core1_stop = false;
    g_core1_period_us = period_us;
    g_core1_list_ptr = list;
    __dmb();
    fifo_try_push(CORE1_CMD_START);
}

static void plat_signal_stop(void)
{
    g_core1_stop = true;
    __dmb();
    fifo_try_push(CORE1_CMD_STOP);
}

static void plat_note_scan(void)
{
    telemetry_note_scan();
}

static void plat_sync_reset(void)
{
    rotation_sync_reset();
}

static void plat_sync_set_sim(bool enabled)
{
    rotation_sync_set_sim(enabled);
}

static void plat_sync_service(void)
{
    rotation_sync_service();
}

static bool plat_sync_take_rev(RotationSnapshot *out)
{
    return rotation_sync_take_rev(out);
}

static bool plat_sync_take_lost(void)
{
    return rotation_sync_take_sync_lost();
}

static RotationSnapshot plat_sync_snapshot(void)
{
    return rotation_sync_snapshot();
}

static const PovPlatform g_plat = {
    .copy = plat_copy,
    .blank = plat_blank,
    .signal_start = plat_signal_start,
    .signal_stop = plat_signal_stop,
    .note_scan = plat_note_scan,
    .sync_reset = plat_sync_reset,
    .sync_set_sim = plat_sync_set_sim,
    .sync_service = plat_sync_service,
    .sync_take_rev = plat_sync_take_rev,
    .sync_take_lost = plat_sync_take_lost,
    .sync_snapshot = plat_sync_snapshot,
};

static bool core1_abort_check(void)
{
    return core1_should_abort(g_core1_stop, multicore_fifo_rvalid());
}

static void core1_entry(void)
{
    while (true) {
        uint32_t cmd = multicore_fifo_pop_blocking();

        if (cmd == CORE1_CMD_STOP || g_core1_stop) {
            pio_scan_blank();
            g_display_active = false;
            pov_service_release_scan(&g_svc);
            continue;
        }

        if (cmd != CORE1_CMD_START) {
            continue;
        }

        if (g_core1_stop) {
            pio_scan_blank();
            g_display_active = false;
            pov_service_release_scan(&g_svc);
            continue;
        }

        uint32_t period_us = g_core1_period_us;
        const VolumeScanlist *list = (const VolumeScanlist *)g_core1_list_ptr;
        if (list == NULL || period_us == 0) {
            pov_service_release_scan(&g_svc);
            continue;
        }

        g_display_active = true;
        bool finished = pio_scan_run_rev(list, period_us, &core1_abort_check);
        g_display_active = false;
        pov_service_release_scan(&g_svc);

        if (!finished) {
            /* Pending FIFO word (START/STOP) — loop to pop it. */
            continue;
        }
    }
}

void pov_runtime_init(void)
{
    pov_service_init(&g_svc, &g_plat);
    g_core1_period_us = ROTATION_SIM_PERIOD_US;
    g_core1_list_ptr = NULL;
    g_core1_stop = true;
    g_display_active = false;
    g_fifo_overflow = false;
    g_fifo_ovf_logged = false;
}

void pov_runtime_start_core1(void)
{
    multicore_launch_core1(core1_entry);
}

void pov_runtime_set_mode(AppMode mode)
{
    pov_service_set_mode(&g_svc, mode);
}

AppMode pov_runtime_mode(void)
{
    return pov_service_mode(&g_svc);
}

void pov_runtime_set_volume(int volume_id)
{
    pov_service_set_volume(&g_svc, volume_id);
}

int pov_runtime_volume_id(void)
{
    return pov_service_volume_id(&g_svc);
}

void pov_runtime_request_rebake(void)
{
    pov_service_request_rebake(&g_svc);
}

void pov_runtime_service(void)
{
    if (g_fifo_overflow && !g_fifo_ovf_logged) {
        g_fifo_ovf_logged = true;
        telemetry_set_flag(VMOJI_FLAG_FIFO_OVF, true);
        telemetry_log("core1 FIFO overflow");
    }
    pov_service_service(&g_svc);
}

RotationSnapshot pov_runtime_rotation(void)
{
    return pov_service_rotation(&g_svc);
}

bool pov_runtime_display_active(void)
{
    return g_display_active || pov_service_display_active(&g_svc);
}
