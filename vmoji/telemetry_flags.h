// Status flag bits, in a plain C header so the C firmware, the C++ telemetry
// emitter, and the Python host parser all read the same single definition.

#ifndef VMOJI_TELEMETRY_FLAGS_H
#define VMOJI_TELEMETRY_FLAGS_H

#define VMOJI_FLAG_ACTIVITY 0x01u  /* activity pixel currently blinking */
#define VMOJI_FLAG_OVERRUN  0x02u  /* UART ring buffer dropped a byte */
#define VMOJI_FLAG_PAUSED   0x04u  /* scanning suspended by host command */
#define VMOJI_FLAG_TX_DROP  0x08u  /* a telemetry frame was dropped, link too slow */
#define VMOJI_FLAG_SYNC_OK  0x10u  /* IR/sim revolution lock is healthy */
#define VMOJI_FLAG_SIM      0x20u  /* simulated rotation (no IR) */

#endif  /* VMOJI_TELEMETRY_FLAGS_H */
