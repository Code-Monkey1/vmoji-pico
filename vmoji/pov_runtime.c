#include "pov_runtime.h"

#include "pio_scan.h"
#include "pov_service.h"
#include "rotation_sync.h"
#include "telemetry.h"

#include "hardware/sync.h"
#include "pico/multicore.h"
#include "pico/stdlib.h"

#include <string.h>

#define SIG_START 1u

static PovService g_svc;
static volatile uint32_t g_core1_period_us = ROTATION_SIM_PERIOD_US;
static volatile uint8_t g_core1_list;
static volatile bool g_core1_stop = true;
static volatile bool g_display_active;

static void plat_copy(void *dst, const void *src, size_t n)
{
    pio_scan_dma_copy(dst, src, n);
}

static void plat_blank(void)
{
    pio_scan_blank();
}

static void plat_signal_start(uint32_t period_us, uint8_t list_index)
{
    g_core1_stop = false;
    g_core1_period_us = period_us;
    g_core1_list = list_index;
    multicore_fifo_push_blocking(SIG_START);
}

static void plat_signal_stop(void)
{
    g_core1_stop = true;
    multicore_fifo_push_blocking(SIG_START);
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
    if (g_core1_stop) {
        return true;
    }
    return (multicore_fifo_get_status() & 1u) != 0u;
}

static void core1_entry(void)
{
    while (true) {
    wait_start:
        while (multicore_fifo_pop_blocking() != SIG_START) {
        }

        if (g_core1_stop) {
            pio_scan_blank();
            g_display_active = false;
            goto wait_start;
        }

        uint32_t period_us = g_core1_period_us;
        uint8_t list_index = g_core1_list;
        if (list_index > 1u) {
            list_index = 0;
        }

        g_display_active = true;
        bool finished =
            pio_scan_run_rev(pov_service_list(&g_svc, list_index), period_us,
                             &core1_abort_check);
        if (!finished) {
            goto wait_start;
        }
        g_display_active = false;
    }
}

void pov_runtime_init(void)
{
    pov_service_init(&g_svc, &g_plat);
    g_core1_period_us = ROTATION_SIM_PERIOD_US;
    g_core1_list = 0;
    g_core1_stop = true;
    g_display_active = false;
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
