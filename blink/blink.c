#include <stdio.h>
#include <string.h>
#include "pico/stdlib.h"
#include "pico/stdio.h"
#include "pico/time.h"
#include "pico.h"
#include "led-matrix.h"
#include "hardware/uart.h"
#include "hardware/irq.h"
#include "hardware/sync.h"

#define UART_ID uart0
#define BAUD_RATE 115200
#define UART_TX_PIN 0
#define UART_RX_PIN 1
#define EOL "\r\n"

#define UART_RX_BUF 256
static volatile uint8_t uart_rx_storage[UART_RX_BUF];
static volatile uint32_t uart_rx_head;
static volatile uint32_t uart_rx_tail;

#define LINE_MAX 48
static char line_buf[LINE_MAX];
static size_t line_len;

static bool frameBuffer[NB_ROW][NB_COL];

/** Activity pixel (row 7, col 7): blinks for ~duration after a score line or `H` heartbeat. */
static uint64_t activity_blink_until_us;
#define ACTIVITY_PIXEL_ROW 7
#define ACTIVITY_PIXEL_COL 7
#define ACTIVITY_BLINK_HALF_US 250000ULL

static void arm_activity_blink_us(uint32_t duration_us)
{
    uint64_t now = time_us_64();
    uint64_t until = now + (uint64_t)duration_us;
    if (until > activity_blink_until_us) {
        activity_blink_until_us = until;
    }
}

static const uint COL_PINS[NB_COL] = {R1, R6, L1, R4, L8, L2, L7, L4};
static const uint ROW_PINS[NB_ROW] = {R8, R7, R3, L3, R2, L5, L6, R5};

/** 3 columns wide, 5 rows; bit 2 = left pixel, bit 0 = right. Rows map to matrix rows 1..5. */
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
}

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

void matrix_refresh(void)
{
    uint64_t now = time_us_64();
    bool blink_window = now < activity_blink_until_us;
    bool blink_phase = blink_window && (((now / ACTIVITY_BLINK_HALF_US) & 1u) != 0);

    for (int r = 0; r < NB_ROW; r++) {
        matrix_blank();
        sleep_us(MATRIX_BLANK_SETTLE_US);
        for (int c = 0; c < NB_COL; c++) {
            bool on = frameBuffer[r][c];
            if (r == ACTIVITY_PIXEL_ROW && c == ACTIVITY_PIXEL_COL && blink_phase) {
                on = true;
            }
            gpio_put(COL_PINS[c], on);
        }
        gpio_set_dir(ROW_PINS[r], GPIO_OUT);
        gpio_put(ROW_PINS[r], 0);
        sleep_us(MATRIX_ROW_DWELL_US);
        gpio_set_dir(ROW_PINS[r], GPIO_IN);
    }
}

static inline void uart_print(const char *s)
{
    uart_puts(UART_ID, s);
}

static void uart_rx_push(uint8_t ch)
{
    uint32_t head = uart_rx_head;
    uint32_t next = (head + 1u) % UART_RX_BUF;
    if (next != uart_rx_tail) {
        uart_rx_storage[head] = ch;
        uart_rx_head = next;
    }
}

static bool uart_rx_pop(uint8_t *out)
{
    uint32_t ints = save_and_disable_interrupts();
    uint32_t tail = uart_rx_tail;
    uint32_t head = uart_rx_head;
    if (tail == head) {
        restore_interrupts(ints);
        return false;
    }
    *out = uart_rx_storage[tail];
    uart_rx_tail = (tail + 1u) % UART_RX_BUF;
    restore_interrupts(ints);
    return true;
}

static void uart0_irq_handler(void)
{
    while (uart_is_readable(UART_ID)) {
        uint8_t ch = (uint8_t)uart_getc(UART_ID);
        uart_rx_push(ch);
    }
}

static void framebuffer_clear(void)
{
    memset(frameBuffer, 0, sizeof(frameBuffer));
}

static void draw_separator_colon(void)
{
    frameBuffer[2][3] = true;
    frameBuffer[2][4] = true;
    frameBuffer[5][3] = true;
    frameBuffer[5][4] = true;
}

static void draw_digit_3x5(int digit, int start_col)
{
    if (digit < 0 || digit > 9 || start_col < 0 || start_col + 3 > NB_COL) {
        return;
    }
    for (int r = 0; r < 5; r++) {
        uint8_t bits = digit_rows_3x5[digit][r];
        for (int c = 0; c < 3; c++) {
            bool on = (bool)((bits >> (2 - c)) & 1u);
            frameBuffer[1 + r][start_col + c] = on;
        }
    }
}

static void draw_score_digits(int h, int a)
{
    framebuffer_clear();
    draw_digit_3x5(h, 0);
    draw_separator_colon();
    draw_digit_3x5(a, 5);
}

/** `p` must point at 'S'. Expect "S <0-9> <0-9>" with optional spaces. */
static bool process_score_line_from_s(const char *p)
{
    if (*p != 'S') {
        return false;
    }
    p++;
    while (*p == ' ') {
        p++;
    }
    if (*p < '0' || *p > '9') {
        return false;
    }
    int h = *p++ - '0';
    while (*p == ' ') {
        p++;
    }
    if (*p < '0' || *p > '9') {
        return false;
    }
    int a = *p - '0';
    draw_score_digits(h, a);
    arm_activity_blink_us(1500000u);

    char ack[24];
    snprintf(ack, sizeof(ack), "OK %d-%d\n", h, a);
    printf("%s", ack);
    snprintf(ack, sizeof(ack), "OK %d-%d" EOL, h, a);
    uart_puts(UART_ID, ack);
    return true;
}

/** Score line `S …` or poll heartbeat `H` (from PC each NHL poll). Skips leading noise to first S/H. */
static void handle_complete_line(const char *line)
{
    const char *p = line;
    while (*p != '\0' && *p != 'S' && *p != 'H') {
        p++;
    }
    if (*p == 'H') {
        const char *q = p + 1;
        while (*q == ' ') {
            q++;
        }
        if (*q != '\0') {
            return;
        }
        arm_activity_blink_us(900000u);
        return;
    }
    if (*p == 'S') {
        process_score_line_from_s(p);
    }
}

/** Line assembly from UART IRQ ring or USB stdio (single consumer in main). */
static void feed_line_byte(uint8_t ch)
{
    if (ch == '\r') {
        return;
    }
    if (ch == '\n') {
        line_buf[line_len] = '\0';
        if (line_len > 0) {
            handle_complete_line(line_buf);
        }
        line_len = 0;
    } else if (line_len < LINE_MAX - 1) {
        line_buf[line_len++] = (char)ch;
    } else {
        line_len = 0;
    }
}

static void drain_uart_lines(void)
{
    uint8_t ch;
    while (uart_rx_pop(&ch)) {
        feed_line_byte(ch);
    }
}

/** USB CDC (/dev/ttyACM0): same `S h a` lines as UART0 GP1 when using a TTL adapter. */
static void drain_stdio_line_bytes(void)
{
    for (int n = 0; n < 128; n++) {
        int c = getchar_timeout_us(0);
        if (c == PICO_ERROR_TIMEOUT) {
            break;
        }
        if (c < 0 || c > 255) {
            continue;
        }
        feed_line_byte((uint8_t)c);
    }
}

static void uart_setup(void)
{
    uart_init(UART_ID, BAUD_RATE);
    gpio_set_function(UART_TX_PIN, UART_FUNCSEL_NUM(UART_ID, UART_TX_PIN));
    gpio_set_function(UART_RX_PIN, UART_FUNCSEL_NUM(UART_ID, UART_RX_PIN));

    irq_set_exclusive_handler(UART0_IRQ, uart0_irq_handler);
    irq_set_enabled(UART0_IRQ, true);
    uart_set_irqs_enabled(UART_ID, true, false);

    sleep_ms(1000);

    uart_print(EOL);
    uart_print("=====================================" EOL);
    uart_print("=========     8x8 VMOJI     =========" EOL);
    uart_print("=========  UART score mode   ========" EOL);
    uart_print("= USB or UART0: lines like S 2 3   =" EOL);
    uart_print("=====================================" EOL);

    /* Same hint on USB serial (minicom /dev/ttyACM0); UART0 is GP0 TX / GP1 RX. */
    printf("\n=====================================\n");
    printf("=========     8x8 VMOJI     =========\n");
    printf("=========  UART score mode   ========\n");
    printf("= USB or UART0: lines like S 2 3   =\n");
    printf("=====================================\n\n");
}

int main(void)
{
    stdio_init_all();
    uart_setup();

    matrix_init();
    framebuffer_clear();

    while (true) {
        matrix_refresh();
        drain_uart_lines();
        drain_stdio_line_bytes();
    }
}
