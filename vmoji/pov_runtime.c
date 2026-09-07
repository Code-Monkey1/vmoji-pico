#include "pov_runtime.h"

#include "pio_scan.h"
#include "rotation_sync.h"
#include "telemetry.h"
#include "volume_codec.h"
#include "volumes_builtin.h"

#include "hardware/sync.h"
#include "pico/multicore.h"
#include "pico/stdlib.h"

#define SIG_START 1u

static VolumeBuffer g_volume;
static VolumeScanlist g_lists[2];
static volatile uint8_t g_display_list;
static volatile uint32_t g_core1_period_us;
static volatile bool g_rebake_needed = true;
static volatile bool g_display_active;
static volatile bool g_core1_stop;

static AppMode g_mode = APP_MODE_STATIC;
static int g_volume_id = 1;
static RotationSnapshot g_last_rot;

static bool core1_abort_check(void)
{
    if (g_core1_stop) {
        return true;
    }
    return (multicore_fifo_get_status() & 1u) != 0u;
}

static void bake_active_content(void)
{
    VolumeFrame *frame = volume_inactive(&g_volume);
    volumes_builtin_draw(g_volume_id, frame);
    VolumeScanlist baked;
    volume_codec_bake(frame, &baked);

    uint8_t slot = (uint8_t)(g_display_list ^ 1u);
    pio_scan_dma_copy(&g_lists[slot], &baked, sizeof(baked));
    volume_flip(&g_volume);

    uint32_t ints = save_and_disable_interrupts();
    g_display_list = slot;
    g_rebake_needed = false;
    restore_interrupts(ints);
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
        uint8_t list_index = g_display_list;
        if (list_index > 1u) {
            list_index = 0;
        }

        g_display_active = true;
        bool finished = pio_scan_run_rev(&g_lists[list_index], period_us,
                                         &core1_abort_check);
        if (!finished) {
            /* New SIG_START (or stop) arrived — resync immediately. */
            goto wait_start;
        }
        g_display_active = false;
    }
}

void pov_runtime_init(void)
{
    volume_init(&g_volume);
    volume_codec_init();
    g_display_list = 0;
    g_core1_period_us = ROTATION_SIM_PERIOD_US;
    g_rebake_needed = true;
    g_display_active = false;
    g_core1_stop = true;
    g_mode = APP_MODE_STATIC;
    g_volume_id = 1;
    g_last_rot = (RotationSnapshot){0};

    bake_active_content();
}

void pov_runtime_start_core1(void)
{
    multicore_launch_core1(core1_entry);
}

void pov_runtime_set_mode(AppMode mode)
{
    if (mode == g_mode) {
        return;
    }
    g_mode = mode;
    rotation_sync_reset();

    if (mode == APP_MODE_STATIC) {
        g_core1_stop = true;
        multicore_fifo_push_blocking(SIG_START);  /* wake core1 to observe stop */
        pio_scan_blank();
        g_display_active = false;
        rotation_sync_set_sim(false);
    } else if (mode == APP_MODE_SIM) {
        g_core1_stop = false;
        rotation_sync_set_sim(true);
    } else {
        g_core1_stop = false;
        rotation_sync_set_sim(false);
    }
    g_rebake_needed = true;
}

AppMode pov_runtime_mode(void)
{
    return g_mode;
}

void pov_runtime_set_volume(int volume_id)
{
    if (volume_id < 0 || volume_id >= BUILTIN_VOLUME_COUNT) {
        return;
    }
    g_volume_id = volume_id;
    g_rebake_needed = true;
}

int pov_runtime_volume_id(void)
{
    return g_volume_id;
}

void pov_runtime_request_rebake(void)
{
    g_rebake_needed = true;
}

void pov_runtime_service(void)
{
    if (g_mode == APP_MODE_STATIC) {
        return;
    }

    if (g_mode == APP_MODE_SIM) {
        rotation_sync_service();
    }

    if (g_rebake_needed) {
        bake_active_content();
    }

    RotationSnapshot snap;
    if (!rotation_sync_take_rev(&snap)) {
        return;
    }
    g_last_rot = snap;

    if (!snap.sync_ok && g_mode == APP_MODE_POV) {
        g_core1_stop = true;
        multicore_fifo_push_blocking(SIG_START);
        pio_scan_blank();
        g_display_active = false;
        return;
    }

    g_core1_stop = false;
    g_core1_period_us = snap.period_us;
    multicore_fifo_push_blocking(SIG_START);
    telemetry_note_scan();
}

RotationSnapshot pov_runtime_rotation(void)
{
    return g_last_rot.rev_count ? g_last_rot : rotation_sync_snapshot();
}

bool pov_runtime_display_active(void)
{
    return g_display_active;
}
