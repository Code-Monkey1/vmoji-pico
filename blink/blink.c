/*
 * Raspberry Pi Pico (RP2040) - 8x8 LED Matrix Driver
 *
 * Direct-drive multiplexing:
 * - 8 row pins  -> anodes
 * - 8 column pins -> cathodes
 *
 * Assumptions:
 * - LED turns ON when:
 *      row = HIGH
 *      column = LOW
 *
 * - Current limiting resistors are REQUIRED.
 * - Only one row is scanned at a time.
 *
 * SDK:
 *   Raspberry Pi Pico SDK
 *
 * Build:
 *   add_executable(matrix main.c)
 *   target_link_libraries(matrix pico_stdlib hardware_gpio)
 *
 */

#include <stdio.h>
#include "pico/stdlib.h"
#include "led-matrix.h"

/*
 * GPIO assignment
 * Change these to match your wiring.
 */

// Rows (anodes)
const uint ROW_PINS[MATRIX_SIZE] = {
    L1,L2,L3,L4,L5,L6,L7,L8
};

// Columns (cathodes)
const uint COL_PINS[MATRIX_SIZE] = {
    R1,R2,R3,R4,R5,R6,R7,R8
};

/*
 * Frame buffer
 *
 * framebuffer[row][col]
 * 1 = LED ON
 * 0 = LED OFF
 */

uint8_t framebuffer[MATRIX_SIZE][MATRIX_SIZE] = {

    {1,0,0,0,0,0,0,1},
    {0,1,0,0,0,0,1,0},
    {0,0,1,0,0,1,0,0},
    {0,0,0,1,1,0,0,0},
    {0,0,0,1,1,0,0,0},
    {0,0,1,0,0,1,0,0},
    {0,1,0,0,0,0,1,0},
    {1,0,0,0,0,0,0,1}
};

/*
 * Initialize GPIO
 */
void matrix_init(void)
{
    // Init rows
    for (int i = 0; i < MATRIX_SIZE; i++) {
        gpio_init(ROW_PINS[i]);
        gpio_set_dir(ROW_PINS[i], GPIO_OUT);
        gpio_put(ROW_PINS[i], 0);
    }

    // Init columns
    for (int i = 0; i < MATRIX_SIZE; i++) {
        gpio_init(COL_PINS[i]);
        gpio_set_dir(COL_PINS[i], GPIO_OUT);

        // Columns idle HIGH (off)
        gpio_put(COL_PINS[i], 1);
    }
}

/*
 * Turn everything off
 */
void matrix_clear_outputs(void)
{
    // All rows LOW
    for (int r = 0; r < MATRIX_SIZE; r++) {
        gpio_put(ROW_PINS[r], 0);
    }

    // All columns HIGH
    for (int c = 0; c < MATRIX_SIZE; c++) {
        gpio_put(COL_PINS[c], 1);
    }
}

/*
 * Scan and display one frame
 *
 * Must be called repeatedly.
 */
void matrix_refresh(void)
{
    for (int row = 0; row < MATRIX_SIZE; row++) {

        // Disable all rows first
        for (int r = 0; r < MATRIX_SIZE; r++) {
            gpio_put(ROW_PINS[r], 0);
        }

        // Set column states
        for (int col = 0; col < MATRIX_SIZE; col++) {

            if (framebuffer[row][col]) {
                // LED ON -> cathode LOW
                gpio_put(COL_PINS[col], 0);
            } else {
                // LED OFF -> cathode HIGH
                gpio_put(COL_PINS[col], 1);
            }
        }

        // Enable current row
        gpio_put(ROW_PINS[row], 1);

        /*
         * Row dwell time
         * ~1ms gives:
         * 8 rows -> 125Hz refresh
         */
        sleep_us(1000);
    }
}

/*
 * Set individual pixel
 */
void matrix_set_pixel(int row, int col, int value)
{
    if (row < 0 || row >= MATRIX_SIZE) return;
    if (col < 0 || col >= MATRIX_SIZE) return;

    framebuffer[row][col] = value ? 1 : 0;
}

/*
 * Clear framebuffer
 */
void matrix_clear(void)
{
    for (int r = 0; r < MATRIX_SIZE; r++) {
        for (int c = 0; c < MATRIX_SIZE; c++) {
            framebuffer[r][c] = 0;
        }
    }
}

/*
 * Example animation
 */
void draw_checkerboard(void)
{
    for (int r = 0; r < MATRIX_SIZE; r++) {
        for (int c = 0; c < MATRIX_SIZE; c++) {
            framebuffer[r][c] = (r + c) % 2;
        }
    }
}

int main()
{
    stdio_init_all();

    matrix_init();

    absolute_time_t last_toggle = get_absolute_time();

    int mode = 0;

    while (1) {

        /*
         * Refresh continuously
         * Multiplexing requires constant scanning.
         */
        matrix_refresh();

        /*
         * Change pattern every second
         */
        if (absolute_time_diff_us(last_toggle, get_absolute_time()) > 1000000) {

            last_toggle = get_absolute_time();

            if (mode == 0) {

                draw_checkerboard();

            } else {

                matrix_clear();

                // Draw border
                for (int i = 0; i < 8; i++) {
                    matrix_set_pixel(0, i, 1);
                    matrix_set_pixel(7, i, 1);
                    matrix_set_pixel(i, 0, 1);
                    matrix_set_pixel(i, 7, 1);
                }
            }

            mode ^= 1;
        }
    }
}