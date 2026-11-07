// UART0 as a command link: interrupt-driven receive into a ring buffer.
//
// The interrupt handler stays short and knows nothing about commands or
// telemetry beyond handing the transmit half to the emitter. Received bytes are
// buffered and consumed by the main loop, so parsing never happens at interrupt
// time - a long command must not be able to stall the scan.

#ifndef VMOJI_UART_LINK_H
#define VMOJI_UART_LINK_H

#include <stdbool.h>
#include <stdint.h>

#include "hardware/uart.h"

#ifdef __cplusplus
extern "C" {
#endif

#define UART_LINK_ID uart0
#define UART_LINK_BAUD 115200

/** Bring up UART0, install the interrupt handler and print the boot banner. */
void uart_link_init(void);

/**
 * Take one received byte, if any.
 *
 * Single consumer, called from the main loop. Returns false when the ring is
 * empty.
 */
bool uart_link_pop(uint8_t *out);

/**
 * Report and clear what the interrupt handler observed since the last call:
 * whether the ring overflowed, and how many bytes have arrived.
 *
 * Moving these out of the ISR is deliberate; the handler must not reach into
 * the telemetry module.
 */
void uart_link_drain_stats(bool *overrun, uint32_t *new_bytes);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_UART_LINK_H
