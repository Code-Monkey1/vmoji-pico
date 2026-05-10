/**
 * Copyright (c) 2020 Raspberry Pi (Trading) Ltd.
 *
 * SPDX-License-Identifier: BSD-3-Clause
 */

#include "pico/stdlib.h"
#include "./blink.h"

uint i;

// Perform initialisation
int pico_led_init(void) {
    // A device like Pico that uses a GPIO for the LED will define PICO_DEFAULT_LED_PIN
    // so we can use normal GPIO functionality to turn the led on and off
    gpio_init(PICO_DEFAULT_LED_PIN);
    gpio_set_dir(PICO_DEFAULT_LED_PIN, GPIO_OUT);

    uint leds[] = {PICO_DEFAULT_LED_PIN, L1, L2, L3, L4, L5, L6, L7, L8, R1, R2, R2, R3, R4, R5, R6, R7, R8};

    for (i = 0; i < 3; i++) {
        gpio_init(leds[i]);
        gpio_set_dir(leds[i], GPIO_OUT);
    }

    return PICO_OK;
}

void gpio_toggle(uint pin) {
    gpio_xor_mask(1u << pin);
}

int main() {
    int rc = pico_led_init();
    hard_assert(rc == PICO_OK);
    while (true) {
        gpio_toggle(L1);
        sleep_ms(LED_DELAY_MS);
        gpio_toggle(L1);
        sleep_ms(LED_DELAY_MS);
        gpio_toggle(R1);
        sleep_ms(LED_DELAY_MS);
        gpio_toggle(R1);
        sleep_ms(LED_DELAY_MS);
        sleep_ms(LED_DELAY_MS*2);
    }
}
