// Single source of board pin numbers and matrix bit masks.
//
// Every driver that touches a GPIO reads from here so a wiring change is one
// edit, not a hunt through scan / sync / codec translation units.

#ifndef VMOJI_BOARD_PINS_H
#define VMOJI_BOARD_PINS_H

#include <stdint.h>

#include "led-matrix.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Once-per-rev IR index */
#ifndef INDEX_IR_GPIO
#define INDEX_IR_GPIO 13
#endif

/*
 * Free GPIOs on the Pico (0-28) after matrix + UART0 + IR:
 *   3, 4, 7, 8, 10, 14, 15, 23, 24, 25
 * GP23-25 are typically board-reserved on a Pico (SMPS / LED).
 */

/** Column anodes, left-to-right as mounted (diameter geometry: ±radius). */
static inline const uint8_t *board_col_pins(void)
{
    static const uint8_t pins[NB_COL] = {
        R1, R6, L1, R4, L8, L2, L7, L4
    };
    return pins;
}

/** Row cathodes, bottom-to-top as mounted (Z up). */
static inline const uint8_t *board_row_pins(void)
{
    static const uint8_t pins[NB_ROW] = {
        R8, R7, R3, L3, R2, L5, L6, R5
    };
    return pins;
}

/** Bit mask of every GPIO used by the LED matrix. */
static inline uint32_t board_matrix_pin_mask(void)
{
    uint32_t mask = 0;
    const uint8_t *cols = board_col_pins();
    const uint8_t *rows = board_row_pins();
    for (int i = 0; i < NB_COL; i++) {
        mask |= (1u << cols[i]);
    }
    for (int i = 0; i < NB_ROW; i++) {
        mask |= (1u << rows[i]);
    }
    return mask;
}

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_BOARD_PINS_H
