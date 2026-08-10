#include <stdio.h>
#include <string.h>
#include "pico/stdlib.h"
#include "pico/stdio.h"
#include "pico/time.h"
#include "pico.h"
#include "led-matrix.h"
#include "telemetry.h"
#include "hardware/uart.h"
#include "hardware/irq.h"
#include "hardware/sync.h"
#include "hardware/watchdog.h"

/* Generous next to a ~3 ms scan: long enough that a slow interval is never
 * mistaken for a hang, short enough that a real lockup recovers on its own. */
#define WATCHDOG_TIMEOUT_MS 2000

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
#define LINE_IDLE_RESET_US 250000ULL
static char line_buf[LINE_MAX];
static size_t line_len;
static bool line_overflow;
static uint64_t line_last_byte_us;

static bool frameBuffer[NB_ROW][NB_COL];

/** Runtime-adjustable so the dashboard can trade refresh rate against
 *  brightness while watching the effect on the live jitter plot. */
static uint16_t row_dwell_us = MATRIX_ROW_DWELL_US;
static bool scan_paused = false;

/** Set from the UART ISR, consumed in the main loop: the ISR must stay short
 *  and must not reach into the telemetry module. */
static volatile bool uart_overrun;
static volatile uint32_t uart_rx_total;

/** Glyphs selectable with the `G <id>` command. Row-major, one byte per row,
 *  bit 7 is column 0. */
#define GLYPH_COUNT 6
static const uint8_t glyphs[GLYPH_COUNT][NB_ROW] = {
    {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00},  /* 0: blank */
    {0x66, 0x99, 0x99, 0x89, 0x81, 0x42, 0x24, 0x18},  /* 1: heart */
    {0xFC, 0xCC, 0xCC, 0xFC, 0xC0, 0xC0, 0xC0, 0xC0},  /* 2: letter P */
    {0xFC, 0xCC, 0xCC, 0xFC, 0xD0, 0xC8, 0xC4, 0xC2},  /* 3: letter R */
    {0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55},  /* 4: checkerboard */
    {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF},  /* 5: all on */
};

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

/** Heartbeat: always restart visible pulse from this moment (each H should blink). */
static void arm_activity_pulse_us(uint32_t duration_us)
{
    uint64_t now = time_us_64();
    activity_blink_until_us = now + (uint64_t)duration_us;
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
        sleep_us(row_dwell_us);
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
        uart_rx_total++;
    } else {
        uart_overrun = true;
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
    /* The same vector carries the transmit interrupt that drains queued
     * telemetry, so the emitter never has to block the scan loop. */
    telemetry_uart_irq();
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
    //draw_separator_colon();
    draw_digit_3x5(a, 5);
}

static void draw_glyph(int glyph_id)
{
    if (glyph_id < 0 || glyph_id >= GLYPH_COUNT) {
        return;
    }
    for (int r = 0; r < NB_ROW; r++) {
        uint8_t bits = glyphs[glyph_id][r];
        for (int c = 0; c < NB_COL; c++) {
            frameBuffer[r][c] = (bool)((bits >> (7 - c)) & 1u);
        }
    }
}

/** Parse a non-negative decimal integer, returning -1 if there are no digits. */
static int parse_uint(const char **cursor)
{
    const char *p = *cursor;
    while (*p == ' ') {
        p++;
    }
    if (*p < '0' || *p > '9') {
        return -1;
    }
    int value = 0;
    while (*p >= '0' && *p <= '9') {
        value = value * 10 + (*p - '0');
        if (value > 1000000) {
            value = 1000000;
        }
        p++;
    }
    *cursor = p;
    return value;
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
    telemetry_set_glyph(0);

    char ack[24];
    snprintf(ack, sizeof(ack), "OK %d-%d", h, a);
    telemetry_ack(ack);
    return true;
}

/**
 * Host commands stay ASCII and line-oriented on purpose: during bring-up you
 * want to be able to drive the board from minicom without any tooling. Only the
 * high-rate telemetry going the other way is binary, where framing and a CRC
 * actually earn their keep.
 *
 *   S <0-9> <0-9>   set the two score digits
 *   H               heartbeat, pulses the activity pixel
 *   G <0-5>         select a glyph
 *   D <us>          set per-row dwell time (50-5000 us)
 *   B               blank the display
 *   P               toggle scan pause
 *   Z               reset counters
 *   ?               report the current configuration
 *   I               report firmware version and unique board id
 */
static void handle_complete_line(const char *line)
{
    const char *p = line;
    while (*p == ' ') {
        p++;
    }

    switch (*p) {
    case 'S': {
        // Every other command answers, so silence here reads as a lost link
        // rather than a rejected score.
        const bool accepted = process_score_line_from_s(p);
        if (!accepted) {
            telemetry_ack("ERR bad score");
        }
        telemetry_note_command(accepted);
        return;
    }

    case 'H':
        arm_activity_pulse_us(800000u);
        telemetry_note_command(true);
        return;

    case 'G': {
        const char *cursor = p + 1;
        int glyph_id = parse_uint(&cursor);
        if (glyph_id < 0 || glyph_id >= GLYPH_COUNT) {
            telemetry_ack("ERR glyph");
            telemetry_note_command(false);
            return;
        }
        draw_glyph(glyph_id);
        telemetry_set_glyph((uint8_t)glyph_id);
        char ack[24];
        snprintf(ack, sizeof(ack), "OK glyph %d", glyph_id);
        telemetry_ack(ack);
        telemetry_note_command(true);
        return;
    }

    case 'D': {
        const char *cursor = p + 1;
        int dwell = parse_uint(&cursor);
        if (dwell < 50 || dwell > 5000) {
            telemetry_ack("ERR dwell 50-5000");
            telemetry_note_command(false);
            return;
        }
        row_dwell_us = (uint16_t)dwell;
        telemetry_set_row_dwell(row_dwell_us);
        char ack[32];
        snprintf(ack, sizeof(ack), "OK dwell %d us", dwell);
        telemetry_ack(ack);
        telemetry_note_command(true);
        return;
    }

    case 'B':
        framebuffer_clear();
        telemetry_set_glyph(0);
        telemetry_ack("OK blank");
        telemetry_note_command(true);
        return;

    case 'P':
        scan_paused = !scan_paused;
        telemetry_set_flag(VMOJI_FLAG_PAUSED, scan_paused);
        if (scan_paused) {
            matrix_blank();
        }
        telemetry_ack(scan_paused ? "OK paused" : "OK running");
        telemetry_note_command(true);
        return;

    case 'Z':
        telemetry_reset_counters();
        telemetry_ack("OK counters cleared");
        telemetry_note_command(true);
        return;

    case '?': {
        char ack[48];
        snprintf(ack, sizeof(ack), "CFG dwell=%u paused=%d", row_dwell_us, (int)scan_paused);
        telemetry_ack(ack);
        telemetry_note_command(true);
        return;
    }

    case 'I':
        telemetry_send_identity();
        telemetry_note_command(true);
        return;

    default:
        /* Acknowledge the rejection. A silent drop here is indistinguishable
         * from a dead link, and it is the one rejection path a stray byte can
         * push an otherwise valid command into. */
        telemetry_ack("ERR unknown");
        telemetry_note_command(false);
        return;
    }
}

/** Line assembly from UART IRQ ring or USB stdio (single consumer in main). */
static void feed_line_byte(uint8_t ch)
{
    uint64_t now = time_us_64();

    /* A byte arriving long after the previous one cannot belong to the same
     * line. Without this a single stray byte - line noise, or a leftover from
     * another program that had the port open - sits in the buffer indefinitely
     * and silently corrupts whatever command is sent next, which then fails
     * with no clue as to why. */
    if ((line_len > 0 || line_overflow) && (now - line_last_byte_us) > LINE_IDLE_RESET_US) {
        line_len = 0;
        line_overflow = false;
    }
    line_last_byte_us = now;

    if (ch == '\r') {
        return;
    }
    if (ch == '\n') {
        if (line_overflow) {
            telemetry_ack("ERR line too long");
            telemetry_note_command(false);
        } else if (line_len > 0) {
            line_buf[line_len] = '\0';
            handle_complete_line(line_buf);
        }
        line_len = 0;
        line_overflow = false;
        return;
    }
    if (line_overflow) {
        return;  /* swallow the rest of the line rather than parsing its tail */
    }
    if (line_len < LINE_MAX - 1) {
        line_buf[line_len++] = (char)ch;
    } else {
        line_overflow = true;
        line_len = 0;
    }
}

static void drain_uart_lines(void)
{
    uint8_t ch;
    while (uart_rx_pop(&ch)) {
        feed_line_byte(ch);
    }

    /* Move ISR-side observations into telemetry from the main loop. */
    if (uart_overrun) {
        uart_overrun = false;
        telemetry_set_flag(VMOJI_FLAG_OVERRUN, true);
    }
    uint32_t total = uart_rx_total;
    static uint32_t reported_rx_total;
    if (total != reported_rx_total) {
        telemetry_note_rx_bytes(total - reported_rx_total);
        reported_rx_total = total;
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
        telemetry_note_rx_bytes(1);
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

    /* Plain-text banner, on the UART only; uart_print does not reach the USB
     * host. Binary telemetry starts immediately afterwards, so this doubles as
     * a test that the host parser can find its sync word in a stream that
     * begins with unframed ASCII. */
    uart_print(EOL);
    uart_print("=====================================" EOL);
    uart_print("=========     8x8 VMOJI     =========" EOL);
    uart_print("===  binary telemetry @ 10 Hz     ===" EOL);
    uart_print("===  commands: S G D B P Z ?      ===" EOL);
    uart_print("=====================================" EOL);
}

int main(void)
{
    stdio_init_all();
    uart_setup();

    matrix_init();
    framebuffer_clear();

    telemetry_init();
    telemetry_log("vmoji telemetry online");
    telemetry_send_identity();

    /* Pause while a debugger has the core halted, so single-stepping does not
     * look like a firmware hang and trigger a reset. */
    watchdog_enable(WATCHDOG_TIMEOUT_MS, true);

    while (true) {
        if (!scan_paused) {
            matrix_refresh();
            telemetry_note_scan();
        }
        drain_uart_lines();
        drain_stdio_line_bytes();
        telemetry_set_flag(VMOJI_FLAG_ACTIVITY, time_us_64() < activity_blink_until_us);
        telemetry_set_framebuffer(&frameBuffer[0][0]);
        telemetry_service();
        watchdog_update();
    }
}
