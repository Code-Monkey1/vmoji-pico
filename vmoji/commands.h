// Host command handling: line assembly and dispatch.
//
// Commands stay ASCII and line-oriented on purpose. Dependencies are injected
// so host tests can exercise parsing without linking matrix / POV / telemetry
// hardware paths.

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

#define DWELL_MIN_US 50
#define DWELL_MAX_US 5000

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

void commands_feed_byte(uint8_t ch);

bool commands_scan_paused(void);

/** Dispatch one complete line (no newline). For unit tests. */
void commands_dispatch_line(const char *line);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_COMMANDS_H
