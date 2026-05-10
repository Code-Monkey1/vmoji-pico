/*
 * 8x8 LED Matrix Auto-Mapping Tool
 * Raspberry Pi Pico (RP2040)
 *
 * Purpose:
 *   Determine which GPIOs connect to:
 *      - rows/anodes
 *      - columns/cathodes
 *
 * Works even if wiring is completely scrambled.
 *
 * Method:
 *   The program lights ONE LED at a time by:
 *
 *      pin A = HIGH
 *      pin B = LOW
 *
 *   Then it prints which pair is active.
 *
 * You observe which LED lights up and record:
 *
 *      GPIO_HIGH -> anode row
 *      GPIO_LOW  -> cathode column
 *
 * --------------------------------------------------------------------
 * HOW TO USE
 * --------------------------------------------------------------------
 *
 * 1. Put the 16 GPIO numbers you used into MATRIX_PINS[].
 *
 * 2. Flash program.
 *
 * 3. Open serial terminal:
 *      115200 baud
 *
 * 4. Program cycles through every possible pair.
 *
 * 5. Each time an LED lights:
 *
 *      terminal shows:
 *
 *          HIGH=GPx LOW=GPy
 *
 * 6. Record the LED position manually.
 *
 * Example:
 *
 *      HIGH=GP4 LOW=GP12
 *      lights LED at row 2 col 5
 *
 * Then:
 *
 *      GP4  = row 2 anode
 *      GP12 = col 5 cathode
 *
 * Repeat until all 64 LEDs are mapped.
 *
 * --------------------------------------------------------------------
 * IMPORTANT
 * --------------------------------------------------------------------
 *
 * Use current limiting resistors.
 * Recommended:
 *      220Ω to 470Ω
 *
 * Only ONE LED is lit at a time.
 */

#include <stdio.h>
#include "pico/stdlib.h"
#include "led-matrix.h"

/*
 * Put ALL GPIOs connected to matrix here.
 * Order does not matter.
 */

const uint MATRIX_PINS[PIN_COUNT] = {
    L1,L2,L3,L4,L5,L6,L7,L8,
    R1,R2,R3,R4,R5,R6,R7,R8
};

/*
 * Initialize all GPIOs
 */
void init_pins(void)
{
    for (int i = 0; i < PIN_COUNT; i++) {

        gpio_init(MATRIX_PINS[i]);
        gpio_set_dir(MATRIX_PINS[i], GPIO_OUT);

        // Hi-Z-ish safe state:
        gpio_put(MATRIX_PINS[i], 0);
    }
}

/*
 * Turn all pins OFF
 */
void all_pins_low(void)
{
    for (int i = 0; i < PIN_COUNT; i++) {
        gpio_put(MATRIX_PINS[i], 0);
    }
}

void all_pins_input(void)
{
    for (int i = 0; i < PIN_COUNT; i++) {

        gpio_set_dir(MATRIX_PINS[i], GPIO_IN);
        gpio_disable_pulls(MATRIX_PINS[i]);
    }
}

void test_pair(uint high_pin, uint low_pin)
{
    // Disconnect everything first
    all_pins_input();

    // HIGH pin
    gpio_set_dir(high_pin, GPIO_OUT);
    gpio_put(high_pin, 1);

    // LOW pin
    gpio_set_dir(low_pin, GPIO_OUT);
    gpio_put(low_pin, 0);
}

int main()
{
    stdio_init_all();

    init_pins();

    sleep_ms(2000);

    printf("\n\n");
    printf("=====================================\n");
    printf("8x8 MATRIX AUTO-MAP TOOL\n");
    printf("=====================================\n");

    while (1) {

        /*
         * Try every HIGH/LOW pair
         */
        for (int hi = 0; hi < PIN_COUNT; hi++) {

            for (int lo = 0; lo < PIN_COUNT; lo++) {

                if (hi == lo)
                    continue;

                uint high_pin = MATRIX_PINS[hi];
                uint low_pin  = MATRIX_PINS[lo];

                /*
                 * Activate pair
                 */
                test_pair(high_pin, low_pin);

                /*
                 * Print mapping info
                 */
                printf("HIGH=GP%d  LOW=GP%d\n",
                       high_pin,
                       low_pin);

                /*
                 * Observe LED
                 */
                sleep_ms(100);
            }
        }
    }
}