#include <stdio.h>
#include <string.h>
#include "pico/stdlib.h"
#include "led-matrix.h"
#include "hardware/uart.h"

// UART communication for debug info
#define UART_ID uart0
#define BAUD_RATE 115200
#define UART_TX_PIN 0
#define UART_RX_PIN 1
#define EOL "\r\n" // End of Line for UART

// GPIO pins to set to HIGH to activate a column
static const uint COL_PINS[NB_COL] = {R1,R6,L1,R4,L8,L2,L7,L4};

// GPIO pins to set to LOW to activate a row
static const uint ROW_PINS[NB_ROW] = {R8,R7,R3,L3,R2,L5,L6,R5};

static uint8_t frameBuffer[NB_ROW][NB_COL] = {0}; // Rows and columns. 0 for LEDs that should be OFF, 1 for ON
char textBuffer[50]; // Ensure this is large enough for your data + null terminator

/** All columns LOW, all rows HIGH: no LED has both column source and row sink active. */
void matrix_blank(void)
{
    for (int i = 0; i < NB_COL; i++) {
        gpio_put(COL_PINS[i], 0);
    }
    for (int i = 0; i < NB_ROW; i++) {
        gpio_put(ROW_PINS[i], 1);
    }
}

/*
 * Put ALL matrix pins into high impedance.
 *
 * This is critical.
 */
void matrix_all_inputs(void)
{
    for (int i = 0; i < MATRIX_SIZE; i++) {

        gpio_set_dir(ROW_PINS[i], GPIO_IN);
        gpio_disable_pulls(ROW_PINS[i]);

        gpio_set_dir(COL_PINS[i], GPIO_IN);
        gpio_disable_pulls(COL_PINS[i]);
    }
}

/*
 * Initialize GPIO hardware: all matrix pins as outputs in a defined blank state.
 */
void matrix_init(void)
{
    for (int i = 0; i < MATRIX_SIZE; i++) {

        gpio_init(ROW_PINS[i]);
        gpio_init(COL_PINS[i]);
        gpio_set_dir(ROW_PINS[i], GPIO_OUT);
        gpio_set_dir(COL_PINS[i], GPIO_OUT);
    }

    matrix_blank();
}

/*
 * Blank, settle, then turn on a single pixel (one column HIGH, one row LOW).
 * Caller controls dwell time (e.g. sleep_ms after this returns).
 */
void matrix_pixel_on(uint row, uint col)
{
    if (row >= NB_ROW || col >= NB_COL) {
        return;
    }
    matrix_blank();
    sleep_us(5);
    gpio_put(COL_PINS[col], 1);
    gpio_put(ROW_PINS[row], 0);
}

/*
 * Full frame multiplex from frameBuffer: deferred until walking-pixel wiring is validated.
 */
void matrix_refresh(void)
{
}

static inline void uart_print(const char *s) {
    uart_puts(UART_ID, s);
}

static void uart_setup() {
    uart_init(UART_ID, BAUD_RATE);
    gpio_set_function(UART_TX_PIN, UART_FUNCSEL_NUM(UART_ID, UART_TX_PIN));
    gpio_set_function(UART_RX_PIN, UART_FUNCSEL_NUM(UART_ID, UART_RX_PIN));

    sleep_ms(1000);

    uart_print(EOL);
    uart_print("=====================================" EOL);
    uart_print("=========     8x8 VMOJI     =========" EOL);
    uart_print("=====================================" EOL);
}

int main(void)
{
    stdio_init_all();
    uart_setup();

    matrix_init();

    while (1) {
        for (uint idx = 0; idx < (uint)(NB_ROW * NB_COL); idx++) {
            uint row = idx / NB_COL;
            uint col = idx % NB_COL;
            matrix_pixel_on(row, col);
            sleep_ms(LED_DELAY_MS);
        }
    }
}