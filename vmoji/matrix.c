#include "matrix.h"

#include <string.h>

#include "hardware/gpio.h"
#include "pico/stdlib.h"
#include "pico/time.h"

/** Activity pixel (row 7, col 7): blinks after a score line or `H` heartbeat. */
#define ACTIVITY_PIXEL_ROW 7
#define ACTIVITY_PIXEL_COL 7
#define ACTIVITY_BLINK_HALF_US 250000ULL

static const uint COL_PINS[NB_COL] = {R1, R6, L1, R4, L8, L2, L7, L4};
static const uint ROW_PINS[NB_ROW] = {R8, R7, R3, L3, R2, L5, L6, R5};

static bool frame_buffer[NB_ROW][NB_COL];

/** Runtime-adjustable so the dashboard can trade refresh rate against
 *  brightness while watching the effect on the live jitter plot. */
static uint16_t row_dwell_us = MATRIX_ROW_DWELL_US;

static uint64_t activity_blink_until_us;

/** Glyphs selectable with the `G <id>` command. Row-major, one byte per row,
 *  bit 7 is column 0. */
static const uint8_t glyphs[GLYPH_COUNT][NB_ROW] = {
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},  /* 0: blank */
    {0x66, 0x99, 0x99, 0x89, 0x81, 0x42, 0x24, 0x18},  /* 1: heart */
    {0xFC, 0xCC, 0xCC, 0xFC, 0xC0, 0xC0, 0xC0, 0xC0},  /* 2: letter P */
    {0xFC, 0xCC, 0xCC, 0xFC, 0xD0, 0xC8, 0xC4, 0xC2},  /* 3: letter R */
    {0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55},  /* 4: checkerboard */
    {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF},  /* 5: all on */
};

/** 3 columns wide, 5 rows; bit 2 = left pixel, bit 0 = right. */
static const uint8_t digit_rows_3x5[10][5] = {
    {0b111, 0b101, 0b101, 0b101, 0b111},
    {0b010, 0b110, 0b010, 0b010, 0b111},
    {0b111, 0b001, 0b111, 0b100, 0b111},
    {0b111, 0b001, 0b111, 0b001, 0b111},
    {0b101, 0b101, 0b111, 0b001, 0b001},
    {0b111, 0b100, 0b111, 0b001, 0b111},
    {0b111, 0b100, 0b111, 0b101, 0b111},
    {0b111, 0b001, 0b001, 0b001, 0b001},
    {0b111, 0b101, 0b111, 0b101, 0b111},
    {0b111, 0b101, 0b111, 0b001, 0b111},
};

void matrix_blank(void)
{
    for (int i = 0; i < NB_COL; i++) {
        gpio_put(COL_PINS[i], 0);
    }
    for (int i = 0; i < NB_ROW; i++) {
        gpio_set_dir(ROW_PINS[i], GPIO_IN);
    }
}

void matrix_init(void)
{
    for (int i = 0; i < MATRIX_SIZE; i++) {
        gpio_init(ROW_PINS[i]);
        gpio_init(COL_PINS[i]);
        gpio_set_dir(ROW_PINS[i], GPIO_IN);
        gpio_set_dir(COL_PINS[i], GPIO_OUT);
    }
    matrix_blank();
    matrix_clear();
}

void matrix_refresh(void)
{
    uint64_t now = time_us_64();
    bool blink_window = now < activity_blink_until_us;
    bool blink_phase = blink_window && (((now / ACTIVITY_BLINK_HALF_US) & 1u) != 0);

    for (int r = 0; r < NB_ROW; r++) {
        matrix_blank();
        sleep_us(MATRIX_BLANK_SETTLE_US);
        for (int c = 0; c < NB_COL; c++) {
            bool on = frame_buffer[r][c];
            if (r == ACTIVITY_PIXEL_ROW && c == ACTIVITY_PIXEL_COL && blink_phase) {
                on = true;
            }
            gpio_put(COL_PINS[c], on);
        }
        gpio_set_dir(ROW_PINS[r], GPIO_OUT);
        gpio_put(ROW_PINS[r], 0);
        sleep_us(row_dwell_us);
        gpio_set_dir(ROW_PINS[r], GPIO_IN);
    }
}

const bool *matrix_framebuffer(void)
{
    return &frame_buffer[0][0];
}

void matrix_set_row_dwell(uint16_t microseconds)
{
    row_dwell_us = microseconds;
}

uint16_t matrix_row_dwell(void)
{
    return row_dwell_us;
}

void matrix_clear(void)
{
    memset(frame_buffer, 0, sizeof(frame_buffer));
}

void matrix_draw_glyph(int glyph_id)
{
    if (glyph_id < 0 || glyph_id >= GLYPH_COUNT) {
        return;
    }
    for (int r = 0; r < NB_ROW; r++) {
        uint8_t bits = glyphs[glyph_id][r];
        for (int c = 0; c < NB_COL; c++) {
            frame_buffer[r][c] = (bool)((bits >> (7 - c)) & 1u);
        }
    }
}

static void draw_digit_3x5(int digit, int start_col)
{
    if (digit < 0 || digit > 9 || start_col < 0 || start_col + 3 > NB_COL) {
        return;
    }
    for (int r = 0; r < 5; r++) {
        uint8_t bits = digit_rows_3x5[digit][r];
        for (int c = 0; c < 3; c++) {
            frame_buffer[1 + r][start_col + c] = (bool)((bits >> (2 - c)) & 1u);
        }
    }
}

void matrix_draw_score(int home, int away)
{
    matrix_clear();
    draw_digit_3x5(home, 0);
    draw_digit_3x5(away, 5);
}

void matrix_arm_activity(uint32_t duration_us, bool extend)
{
    uint64_t until = time_us_64() + (uint64_t)duration_us;
    if (extend && until < activity_blink_until_us) {
        return;
    }
    activity_blink_until_us = until;
}

bool matrix_activity_pending(void)
{
    return time_us_64() < activity_blink_until_us;
}
