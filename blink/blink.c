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
        gpio_set_dir(ROW_PINS[i], GPIO_IN);
    }
}

/*
 * Initialize GPIO hardware
 */
void matrix_init(void)
{
    for (int i = 0; i < MATRIX_SIZE; i++) {

        gpio_init(ROW_PINS[i]);
        gpio_init(COL_PINS[i]);
        gpio_set_dir(ROW_PINS[i], GPIO_IN);
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
    sleep_us(MATRIX_BLANK_SETTLE_US);
    gpio_put(COL_PINS[col], 1);
    gpio_put(ROW_PINS[row], 0);
}

/*
 * One full scan of frameBuffer: exactly one row sunk at a time; columns follow row data.
 * Blank between rows to avoid ghosting (same ordering as matrix_pixel_on).
 */
void matrix_refresh(void)
{
    for (int r = 0; r < NB_ROW; r++) {
        matrix_blank();
        sleep_us(MATRIX_BLANK_SETTLE_US);
        for (int c = 0; c < NB_COL; c++) {
            gpio_put(COL_PINS[c], frameBuffer[r][c]);
        }
        gpio_set_dir(ROW_PINS[r], GPIO_OUT);
        gpio_put(ROW_PINS[r], 0);
        sleep_us(MATRIX_ROW_DWELL_US);
        gpio_set_dir(ROW_PINS[r], GPIO_IN);
    }
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

    for (int r = 0; r < NB_ROW; r++) {
        for (int c = 0; c < NB_COL; c++) {
            frameBuffer[r][c] = (uint8_t)(((r ^ c) & 1) != 0); // chess board pattern
        }
    }

    while (1) {
        matrix_refresh();
    }
}