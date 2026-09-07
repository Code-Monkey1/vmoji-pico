#include "commands.h"

#include <stdio.h>
#include <string.h>

#include "app_mode.h"
#include "matrix.h"
#include "pico/stdlib.h"
#include "pico/time.h"
#include "pov_runtime.h"
#include "telemetry.h"
#include "volumes_builtin.h"

#define LINE_MAX 48
#define LINE_IDLE_RESET_US 250000ULL

#define ACK_MAX 80

#define ACTIVITY_SCORE_US 1500000u
#define ACTIVITY_HEARTBEAT_US 800000u

static char line_buf[LINE_MAX];
static size_t line_len;
static bool line_overflow;
static uint64_t line_last_byte_us;

static bool scan_paused;

bool commands_scan_paused(void)
{
    return scan_paused;
}

static int parse_uint(const char *cursor)
{
    while (*cursor == ' ') {
        cursor++;
    }
    if (*cursor < '0' || *cursor > '9') {
        return -1;
    }
    int value = 0;
    while (*cursor >= '0' && *cursor <= '9') {
        value = value * 10 + (*cursor - '0');
        if (value > 1000000) {
            value = 1000000;
        }
        cursor++;
    }
    return value;
}

typedef bool (*command_fn)(const char *args, char *ack, size_t ack_size);

static bool cmd_score(const char *args, char *ack, size_t ack_size)
{
    while (*args == ' ') {
        args++;
    }
    if (*args < '0' || *args > '9') {
        snprintf(ack, ack_size, "ERR bad score");
        return false;
    }
    int home = *args++ - '0';
    while (*args == ' ') {
        args++;
    }
    if (*args < '0' || *args > '9') {
        snprintf(ack, ack_size, "ERR bad score");
        return false;
    }
    int away = *args - '0';

    matrix_draw_score(home, away);
    matrix_arm_activity(ACTIVITY_SCORE_US, true);
    telemetry_set_glyph(0);
    snprintf(ack, ack_size, "OK %d-%d", home, away);
    return true;
}

static bool cmd_heartbeat(const char *args, char *ack, size_t ack_size)
{
    (void)args;
    matrix_arm_activity(ACTIVITY_HEARTBEAT_US, false);
    snprintf(ack, ack_size, "OK heartbeat");
    return true;
}

static bool cmd_glyph(const char *args, char *ack, size_t ack_size)
{
    int glyph_id = parse_uint(args);
    if (glyph_id < 0 || glyph_id >= GLYPH_COUNT) {
        snprintf(ack, ack_size, "ERR glyph");
        return false;
    }
    matrix_draw_glyph(glyph_id);
    telemetry_set_glyph((uint8_t)glyph_id);
    snprintf(ack, ack_size, "OK glyph %d", glyph_id);
    return true;
}

static bool cmd_dwell(const char *args, char *ack, size_t ack_size)
{
    int dwell = parse_uint(args);
    if (dwell < DWELL_MIN_US || dwell > DWELL_MAX_US) {
        snprintf(ack, ack_size, "ERR dwell %d-%d", DWELL_MIN_US, DWELL_MAX_US);
        return false;
    }
    matrix_set_row_dwell((uint16_t)dwell);
    telemetry_set_row_dwell((uint16_t)dwell);
    snprintf(ack, ack_size, "OK dwell %d us", dwell);
    return true;
}

static bool cmd_blank(const char *args, char *ack, size_t ack_size)
{
    (void)args;
    matrix_clear();
    telemetry_set_glyph(0);
    snprintf(ack, ack_size, "OK blank");
    return true;
}

static bool cmd_pause(const char *args, char *ack, size_t ack_size)
{
    (void)args;
    scan_paused = !scan_paused;
    telemetry_set_flag(VMOJI_FLAG_PAUSED, scan_paused);
    if (scan_paused) {
        matrix_blank();
    }
    snprintf(ack, ack_size, "%s", scan_paused ? "OK paused" : "OK running");
    return true;
}

static bool cmd_reset_counters(const char *args, char *ack, size_t ack_size)
{
    (void)args;
    telemetry_reset_counters();
    snprintf(ack, ack_size, "OK counters cleared");
    return true;
}

static bool cmd_mode(const char *args, char *ack, size_t ack_size)
{
    while (*args == ' ') {
        args++;
    }
    AppMode mode;
    if (strncmp(args, "static", 6) == 0) {
        mode = APP_MODE_STATIC;
    } else if (strncmp(args, "pov", 3) == 0) {
        mode = APP_MODE_POV;
    } else if (strncmp(args, "sim", 3) == 0) {
        mode = APP_MODE_SIM;
    } else {
        snprintf(ack, ack_size, "ERR mode static|pov|sim");
        return false;
    }
    pov_runtime_set_mode(mode);
    const char *name = mode == APP_MODE_STATIC ? "static"
                       : mode == APP_MODE_POV   ? "pov"
                                                : "sim";
    snprintf(ack, ack_size, "OK mode %s", name);
    return true;
}

static bool cmd_volume(const char *args, char *ack, size_t ack_size)
{
    int id = parse_uint(args);
    if (id < 0 || id >= BUILTIN_VOLUME_COUNT) {
        snprintf(ack, ack_size, "ERR volume 0-%d", BUILTIN_VOLUME_COUNT - 1);
        return false;
    }
    pov_runtime_set_volume(id);
    snprintf(ack, ack_size, "OK volume %d %s", id, volumes_builtin_name(id));
    return true;
}

static bool cmd_query(const char *args, char *ack, size_t ack_size)
{
    (void)args;
    AppMode mode = pov_runtime_mode();
    const char *mode_name = mode == APP_MODE_STATIC ? "static"
                            : mode == APP_MODE_POV   ? "pov"
                                                     : "sim";
    RotationSnapshot rot = pov_runtime_rotation();
    snprintf(ack, ack_size,
             "CFG mode=%s vol=%d dwell=%u paused=%d rpm=%u period=%lu",
             mode_name, pov_runtime_volume_id(), matrix_row_dwell(),
             (int)scan_paused, (unsigned)rot.rpm,
             (unsigned long)rot.period_us);
    return true;
}

static bool cmd_identity(const char *args, char *ack, size_t ack_size)
{
    (void)args;
    (void)ack_size;
    telemetry_send_identity();
    ack[0] = '\0';
    return true;
}

static const struct {
    char verb;
    command_fn handle;
} kCommands[] = {
    {'S', cmd_score},
    {'H', cmd_heartbeat},
    {'G', cmd_glyph},
    {'D', cmd_dwell},
    {'B', cmd_blank},
    {'P', cmd_pause},
    {'Z', cmd_reset_counters},
    {'M', cmd_mode},
    {'V', cmd_volume},
    {'?', cmd_query},
    {'I', cmd_identity},
};

static void handle_complete_line(const char *line)
{
    while (*line == ' ') {
        line++;
    }

    char ack[ACK_MAX];
    bool accepted = false;
    command_fn handler = NULL;

    for (size_t i = 0; i < count_of(kCommands); i++) {
        if (kCommands[i].verb == *line) {
            handler = kCommands[i].handle;
            break;
        }
    }

    if (handler != NULL) {
        accepted = handler(line + 1, ack, sizeof(ack));
    } else {
        snprintf(ack, sizeof(ack), "ERR unknown");
    }

    if (ack[0] != '\0') {
        telemetry_ack(ack);
    }
    telemetry_note_command(accepted);
}

void commands_feed_byte(uint8_t ch)
{
    uint64_t now = time_us_64();

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
        return;
    }
    if (line_len < LINE_MAX - 1) {
        line_buf[line_len++] = (char)ch;
    } else {
        line_overflow = true;
        line_len = 0;
    }
}
