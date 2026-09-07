// Pure IR edge refractory check (no GPIO).

#ifndef VMOJI_IR_DEBOUNCE_H
#define VMOJI_IR_DEBOUNCE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Default: ignore edges within 500 µs of the last accepted edge. */
#ifndef IR_REFRACTORY_US
#define IR_REFRACTORY_US 500u
#endif

/**
 * True if now_us should be accepted as a new index edge.
 * last_accepted_us == 0 means no prior edge (always accept).
 */
bool ir_accept_edge(uint64_t last_accepted_us, uint64_t now_us,
                    uint32_t refractory_us);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_IR_DEBOUNCE_H
