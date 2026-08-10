#include "uart_link.h"

#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "hardware/sync.h"
#include "pico/stdlib.h"
#include "telemetry.h"

#define UART_TX_PIN 0
#define UART_RX_PIN 1
#define EOL "\r\n"

#define UART_RX_BUF 256
static volatile uint8_t rx_storage[UART_RX_BUF];
static volatile uint32_t rx_head;
static volatile uint32_t rx_tail;

static volatile bool rx_overrun;
static volatile uint32_t rx_total;
static uint32_t reported_rx_total;

static void rx_push(uint8_t ch)
{
    uint32_t head = rx_head;
    uint32_t next = (head + 1u) % UART_RX_BUF;
    if (next != rx_tail) {
        rx_storage[head] = ch;
        rx_head = next;
        rx_total++;
    } else {
        rx_overrun = true;
    }
}

bool uart_link_pop(uint8_t *out)
{
    uint32_t ints = save_and_disable_interrupts();
    uint32_t tail = rx_tail;
    if (tail == rx_head) {
        restore_interrupts(ints);
        return false;
    }
    *out = rx_storage[tail];
    rx_tail = (tail + 1u) % UART_RX_BUF;
    restore_interrupts(ints);
    return true;
}

void uart_link_drain_stats(bool *overrun, uint32_t *new_bytes)
{
    if (overrun != NULL) {
        *overrun = rx_overrun;
        if (rx_overrun) {
            rx_overrun = false;
        }
    }
    if (new_bytes != NULL) {
        uint32_t total = rx_total;
        *new_bytes = total - reported_rx_total;
        reported_rx_total = total;
    }
}

static void uart0_irq_handler(void)
{
    while (uart_is_readable(UART_LINK_ID)) {
        rx_push((uint8_t)uart_getc(UART_LINK_ID));
    }
    /* The same vector carries the transmit interrupt that drains queued
     * telemetry, so the emitter never has to block the scan loop. */
    telemetry_uart_irq();
}

static void print_banner(void)
{
    /* Plain text, on the UART only; this does not reach the USB host. Binary
     * telemetry starts immediately afterwards, so the banner doubles as a test
     * that the host parser can find its sync word in a stream that begins with
     * unframed ASCII. */
    static const char *const lines[] = {
        EOL,
        "=====================================" EOL,
        "=========     8x8 VMOJI     =========" EOL,
        "===  binary telemetry @ 10 Hz     ===" EOL,
        "===  commands: S G D B P Z ?      ===" EOL,
        "=====================================" EOL,
    };
    for (size_t i = 0; i < count_of(lines); i++) {
        uart_puts(UART_LINK_ID, lines[i]);
    }
}

void uart_link_init(void)
{
    uart_init(UART_LINK_ID, UART_LINK_BAUD);
    gpio_set_function(UART_TX_PIN, UART_FUNCSEL_NUM(UART_LINK_ID, UART_TX_PIN));
    gpio_set_function(UART_RX_PIN, UART_FUNCSEL_NUM(UART_LINK_ID, UART_RX_PIN));

    irq_set_exclusive_handler(UART0_IRQ, uart0_irq_handler);
    irq_set_enabled(UART0_IRQ, true);
    uart_set_irqs_enabled(UART_LINK_ID, true, false);

    print_banner();
}
