// vmoji: volumetric POV display on the RP2040.
//
// Core 0: commands, telemetry, rotation sync, volume bake.
// Core 1: PIO-paced parallel GPIO scan for each revolution.

#include <stdio.h>

#include "commands.h"
#include "hardware/watchdog.h"
#include "matrix.h"
#include "pico/stdio.h"
#include "pico/stdlib.h"
#include "pico/time.h"
#include "pio_scan.h"
#include "pov_runtime.h"
#include "rotation_sync.h"
#include "telemetry.h"
#include "uart_link.h"
#include "app_mode.h"

#define WATCHDOG_TIMEOUT_MS 2000
#define STDIO_DRAIN_LIMIT 128

static void drain_uart_input(void)
{
    uint8_t ch;
    while (uart_link_pop(&ch)) {
        commands_feed_byte(ch);
    }

    bool overrun = false;
    uint32_t new_bytes = 0;
    uart_link_drain_stats(&overrun, &new_bytes);
    if (overrun) {
        telemetry_set_flag(VMOJI_FLAG_OVERRUN, true);
    }
    if (new_bytes > 0) {
        telemetry_note_rx_bytes(new_bytes);
    }
}

static void drain_stdio_input(void)
{
    for (int n = 0; n < STDIO_DRAIN_LIMIT; n++) {
        int c = getchar_timeout_us(0);
        if (c == PICO_ERROR_TIMEOUT) {
            break;
        }
        if (c < 0 || c > 255) {
            continue;
        }
        telemetry_note_rx_bytes(1);
        commands_feed_byte((uint8_t)c);
    }
}

static void update_pov_telemetry(void)
{
    RotationSnapshot rot = pov_runtime_rotation();
    AppMode mode = pov_runtime_mode();
    telemetry_set_pov(rot.rpm, rot.period_us, (uint8_t)mode,
                      (uint8_t)pov_runtime_volume_id());
    telemetry_set_flag(VMOJI_FLAG_SYNC_OK, rot.sync_ok);
    telemetry_set_flag(VMOJI_FLAG_SIM, mode == APP_MODE_SIM);
}

int main(void)
{
    stdio_init_all();
    uart_link_init();

    pio_scan_init();
    matrix_init();
    rotation_sync_init();
    pov_runtime_init();
    pov_runtime_start_core1();

    telemetry_init();
    telemetry_log("vmoji POV telemetry online");
    telemetry_send_identity();

    watchdog_enable(WATCHDOG_TIMEOUT_MS, true);

    while (true) {
        AppMode mode = pov_runtime_mode();

        if (!commands_scan_paused()) {
            if (mode == APP_MODE_STATIC) {
                matrix_refresh();
                telemetry_note_scan();
            } else {
                pov_runtime_service();
            }
        }

        drain_uart_input();
        drain_stdio_input();
        update_pov_telemetry();
        telemetry_set_flag(VMOJI_FLAG_ACTIVITY, matrix_activity_pending());
        telemetry_set_framebuffer(matrix_framebuffer());
        telemetry_service();
        watchdog_update();
    }
}
