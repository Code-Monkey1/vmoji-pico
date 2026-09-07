// Core1 command words and abort predicate (host-testable).

#ifndef VMOJI_CORE1_CMD_H
#define VMOJI_CORE1_CMD_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define CORE1_CMD_START 1u
#define CORE1_CMD_STOP 2u

/** Abort the in-progress revolution if stop was requested or a new cmd is queued. */
static inline bool core1_should_abort(bool stop_flag, bool fifo_pending)
{
    return stop_flag || fifo_pending;
}

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_CORE1_CMD_H
