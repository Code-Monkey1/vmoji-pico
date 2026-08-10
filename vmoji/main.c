// vmoji: an 8x8 LED matrix driven by a self-measuring scan loop.
//
// This file is only the wiring. The display lives in matrix.c, the UART command
// link in uart_link.c, command parsing in commands.c and the binary downlink in
// telemetry.cpp. The loop below is deliberately short enough to read in one go,
// because its shape - scan, drain input, report, kick the watchdog - is the
// timing contract the whole instrument is built to measure.

#include <stdio.h>

#include "commands.h"
#include "hardware/watchdog.h"
#include "matrix.h"
#include "pico/stdio.h"
#include "pico/stdlib.h"
#include "pico/time.h"
#include "telemetry.h"
#include "uart_link.h"

/* Generous next to a ~3 ms scan: long enough that a slow interval is never
 * mistaken for a hang, short enough that a real lockup recovers on its own. */
#define WATCHDOG_TIMEOUT_MS 2000

/** Bytes taken from USB per pass, so a flood cannot monopolise the loop. */
#define STDIO_DRAIN_LIMIT 128

static void drain_uart_input(void)
{
    uint8_t ch;
    while (uart_link_pop(&ch)) {
        commands_feed_byte(ch);
    }

    /* Move the interrupt handler's observations into telemetry from here, so
     * the ISR itself never reaches into the emitter. */
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

/** USB CDC (/dev/ttyACM0): the same command lines as UART0. */
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

int main(void)
{
    stdio_init_all();
    uart_link_init();
    matrix_init();

    telemetry_init();
    telemetry_log("vmoji telemetry online");
    telemetry_send_identity();

    /* Pause while a debugger has the core halted, so single-stepping does not
     * look like a firmware hang and trigger a reset. */
    watchdog_enable(WATCHDOG_TIMEOUT_MS, true);

    while (true) {
        if (!commands_scan_paused()) {
            matrix_refresh();
            telemetry_note_scan();
        }
        drain_uart_input();
        drain_stdio_input();
        telemetry_set_flag(VMOJI_FLAG_ACTIVITY, matrix_activity_pending());
        telemetry_set_framebuffer(matrix_framebuffer());
        telemetry_service();
        watchdog_update();
    }
}
