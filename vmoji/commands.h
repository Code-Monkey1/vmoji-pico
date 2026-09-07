// Host command handling: line assembly and dispatch.
//
// Commands stay ASCII and line-oriented on purpose: during bring-up you want to
// drive the board from minicom with no tooling at all. Only the high-rate
// telemetry going the other way is binary, where framing and a CRC earn their
// keep. Dependencies are injected so host tests can exercise parsing without
// linking matrix / POV / telemetry hardware paths.
//
//   S <0-9> <0-9>   set the two score digits
//   H               heartbeat, pulses the activity pixel
//   G <0-5>         select a glyph
//   D <us>          set per-row dwell time
//   B               blank the display
//   P               toggle scan pause
//   Z               reset counters
//   M static|pov|sim  operating mode
//   V <id>          builtin volume (POV/sim)
//   ?               report the current configuration
//   I               report firmware version and unique board id

#ifndef VMOJI_COMMANDS_H
#define VMOJI_COMMANDS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "app_mode.h"
#include "rotation_sync.h"

#ifdef __cplusplus
extern "C" {
#endif

/** The dwell range accepted by `D`. Mirrored by the host in protocol.py. */
#define DWELL_MIN_US 50
#define DWELL_MAX_US 5000

/** Injected ops so command parsing can be unit-tested off-target. */
typedef struct {
    uint64_t (*now_us)(void);

    void (*draw_score)(int home, int away);
    void (*arm_activity)(uint32_t duration_us, bool extend);
    void (*draw_glyph)(int glyph_id);
    void (*set_dwell)(uint16_t us);
    uint16_t (*get_dwell)(void);
    void (*clear_matrix)(void);
    void (*blank_matrix)(void);

    void (*set_mode)(AppMode mode);
    AppMode (*get_mode)(void);
    void (*set_volume)(int id);
    int (*get_volume)(void);
    const char *(*volume_name)(int id);
    RotationSnapshot (*get_rotation)(void);

    void (*set_glyph_telemetry)(uint8_t id);
    void (*set_dwell_telemetry)(uint16_t us);
    void (*set_flag)(uint8_t flag, bool on);
    void (*reset_counters)(void);
    void (*send_identity)(void);
    void (*ack)(const char *text);
    void (*note_command)(bool accepted);
} CommandsDeps;

/** Install deps used by feed_byte / dispatch. Call once at boot. */
void commands_set_deps(const CommandsDeps *deps);

/** Wire production matrix / POV / telemetry implementations. */
void commands_init_default(void);

/**
 * Feed one received byte, from either link.
 *
 * Assembles a line and dispatches it on newline. Single consumer: both the UART
 * ring and USB stdio are drained by the main loop, never concurrently.
 */
void commands_feed_byte(uint8_t ch);

/** True while the host has paused scanning with `P`. */
bool commands_scan_paused(void);

/** Dispatch one complete line (no newline). For unit tests. */
void commands_dispatch_line(const char *line);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_COMMANDS_H
