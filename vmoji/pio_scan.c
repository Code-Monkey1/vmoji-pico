#include "pio_scan.h"

#include "board_pins.h"
#include "led-matrix.h"
#include "pio_scan.pio.h"

#include <string.h>

#include "hardware/clocks.h"
#include "hardware/dma.h"
#include "hardware/gpio.h"
#include "hardware/pio.h"
#include "pico/stdlib.h"
#include "pico/time.h"

static PIO g_pio = pio0;
static uint g_sm;
static uint g_offset;
static int g_dma_chan = -1;
static uint32_t g_pin_mask;
static uint32_t g_blank;

static void matrix_pins_init(void)
{
    g_pin_mask = board_matrix_pin_mask();
    const uint8_t *cols = board_col_pins();
    const uint8_t *rows = board_row_pins();
    for (int i = 0; i < NB_COL; i++) {
        gpio_init(cols[i]);
        gpio_set_dir(cols[i], GPIO_OUT);
        gpio_put(cols[i], 0);
    }
    for (int i = 0; i < NB_ROW; i++) {
        gpio_init(rows[i]);
        gpio_set_dir(rows[i], GPIO_OUT);
        gpio_put(rows[i], 1);
    }
    g_blank = 0;
    for (int i = 0; i < NB_ROW; i++) {
        g_blank |= (1u << rows[i]);
    }
}

static void apply_mask(uint32_t word)
{
    gpio_put_masked(g_pin_mask, word);
}

static void pio_delay_cycles(uint32_t cycles)
{
    if (cycles == 0) {
        cycles = 1;
    }
    g_pio->fdebug = 1u << (PIO_FDEBUG_TXSTALL_LSB + g_sm);
    pio_sm_put_blocking(g_pio, g_sm, cycles);
    while (!(g_pio->fdebug & (1u << (PIO_FDEBUG_TXSTALL_LSB + g_sm)))) {
        tight_loop_contents();
    }
    g_pio->fdebug = 1u << (PIO_FDEBUG_TXSTALL_LSB + g_sm);
}

void pio_scan_init(void)
{
    matrix_pins_init();
    apply_mask(g_blank);

    g_offset = pio_add_program(g_pio, &step_delay_program);
    g_sm = pio_claim_unused_sm(g_pio, true);

    pio_sm_config c = step_delay_program_get_default_config(g_offset);
    sm_config_set_out_shift(&c, true, true, 32);
    sm_config_set_fifo_join(&c, PIO_FIFO_JOIN_TX);
    sm_config_set_clkdiv(&c, 1.0f);
    pio_sm_init(g_pio, g_sm, g_offset, &c);
    pio_sm_set_enabled(g_pio, g_sm, true);

    g_dma_chan = dma_claim_unused_channel(true);
}

void pio_scan_blank(void)
{
    apply_mask(g_blank);
}

/** DMA memcpy for scanlist publish (core 0 → core 1 visible buffer). */
void pio_scan_dma_copy(void *dst, const void *src, size_t bytes)
{
    if (g_dma_chan < 0 || bytes == 0) {
        return;
    }
    /* Word-aligned 32-bit transfers. */
    uint32_t count = (uint32_t)((bytes + 3u) / 4u);
    dma_channel_config dc = dma_channel_get_default_config(g_dma_chan);
    channel_config_set_transfer_data_size(&dc, DMA_SIZE_32);
    channel_config_set_read_increment(&dc, true);
    channel_config_set_write_increment(&dc, true);
    dma_channel_configure(g_dma_chan, &dc, dst, src, count, true);
    dma_channel_wait_for_finish_blocking(g_dma_chan);
}

bool pio_scan_run_rev(const VolumeScanlist *list, uint32_t period_us,
                      bool (*abort_check)(void))
{
    if (list == NULL || period_us == 0) {
        return false;
    }

    const uint32_t count = CODEC_STEPS_PER_REV;
    uint32_t step_us = period_us / count;
    if (step_us == 0) {
        step_us = 1;
    }

    const uint32_t sys_hz = clock_get_hz(clk_sys);
    uint32_t delay_cycles = (uint32_t)((uint64_t)step_us * sys_hz / 1000000ull);
    if (delay_cycles > 32u) {
        delay_cycles -= 32u;  /* approximate call/mask overhead */
    } else {
        delay_cycles = 1u;
    }

    g_pin_mask = list->pin_mask;
    g_blank = list->blank;

    for (uint32_t i = 0; i < count; i++) {
        if (abort_check && abort_check()) {
            apply_mask(g_blank);
            return false;
        }
        apply_mask(list->steps[i]);
        pio_delay_cycles(delay_cycles);
    }

    apply_mask(g_blank);
    return true;
}

void pio_scan_static_frame(const uint32_t row_words[8], uint32_t blank,
                           uint32_t pin_mask, uint16_t dwell_us)
{
    g_pin_mask = pin_mask;
    g_blank = blank;
    for (int r = 0; r < 8; r++) {
        apply_mask(blank);
        busy_wait_us_32(MATRIX_BLANK_SETTLE_US);
        apply_mask(row_words[r]);
        busy_wait_us_32(dwell_us);
    }
    apply_mask(blank);
}
