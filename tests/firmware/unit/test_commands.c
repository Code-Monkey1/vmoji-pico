#include "test_harness.h"

#include "commands.h"
#include "fake_time.h"
#include "volumes_builtin.h"

#include <stdio.h>
#include <string.h>

static char g_last_ack[96];
static int g_ack_count;
static int g_cmd_ok;
static int g_cmd_err;
static AppMode g_mode = APP_MODE_STATIC;
static int g_volume = 1;
static uint16_t g_dwell = 400;
static int g_score_home = -1;
static int g_score_away = -1;
static int g_glyph = -1;
static int g_pixel_row = -1;
static int g_pixel_col = -1;
static int g_blank_count;
/* Call order, so the takeover can be checked to come before the draw. */
static int g_seq;
static int g_takeover_count;
static int g_takeover_at = -1;
static int g_pixel_at = -1;
static int g_glyph_at = -1;
static int g_clear_at = -1;
static int g_score_at = -1;
static int g_volume_at = -1;
static int g_mode_at = -1;
static int g_pause_at = -1; /* P's first dep call is set_flag(PAUSED). */
static CommandsDeps g_installed;

static void feed_line(const char *line)
{
    for (const char *p = line; *p; p++) {
        commands_feed_byte((uint8_t)*p);
    }
    commands_feed_byte('\n');
}

static void stub_ack(const char *text)
{
    snprintf(g_last_ack, sizeof(g_last_ack), "%s", text);
    g_ack_count++;
}

static void stub_note(bool ok)
{
    if (ok) {
        g_cmd_ok++;
    } else {
        g_cmd_err++;
    }
}

static void stub_set_mode(AppMode m)
{
    g_mode = m;
    g_mode_at = ++g_seq;
}
static AppMode stub_get_mode(void)
{
    return g_mode;
}
static void stub_set_volume(int id)
{
    g_volume = id;
    g_volume_at = ++g_seq;
}
static int stub_get_volume(void)
{
    return g_volume;
}
static void stub_draw_score(int h, int a)
{
    g_score_home = h;
    g_score_away = a;
    g_score_at = ++g_seq;
}
static void stub_arm(uint32_t us, bool extend)
{
    (void)us;
    (void)extend;
}
static void stub_glyph(int id)
{
    g_glyph = id;
    g_glyph_at = ++g_seq;
}
static void stub_pixel(int row, int col)
{
    g_pixel_row = row;
    g_pixel_col = col;
    g_pixel_at = ++g_seq;
}
static void stub_set_dwell(uint16_t us)
{
    g_dwell = us;
}
static uint16_t stub_get_dwell(void)
{
    return g_dwell;
}
static void stub_clear(void)
{
    g_clear_at = ++g_seq;
}
static void stub_blank(void)
{
    g_blank_count++;
}
static void stub_set_glyph_tel(uint8_t id)
{
    (void)id;
}
static void stub_set_dwell_tel(uint16_t us)
{
    (void)us;
}
static void stub_flag(uint8_t f, bool on)
{
    (void)f;
    (void)on;
    g_pause_at = ++g_seq;
}
static void stub_reset(void) {}
static void stub_takeover(void)
{
    g_takeover_count++;
    g_takeover_at = ++g_seq;
}
static void stub_identity(void) {}
static RotationSnapshot stub_rot(void)
{
    RotationSnapshot s = {0};
    s.rpm = 1000;
    s.period_us = 60000;
    return s;
}

static void install_stubs(void)
{
    g_installed = (CommandsDeps){
        .now_us = fake_time_now_us,
        .draw_score = stub_draw_score,
        .arm_activity = stub_arm,
        .draw_glyph = stub_glyph,
        .draw_pixel = stub_pixel,
        .set_dwell = stub_set_dwell,
        .get_dwell = stub_get_dwell,
        .clear_matrix = stub_clear,
        .blank_matrix = stub_blank,
        .set_mode = stub_set_mode,
        .get_mode = stub_get_mode,
        .set_volume = stub_set_volume,
        .get_volume = stub_get_volume,
        .volume_name = volumes_builtin_name,
        .get_rotation = stub_rot,
        .set_glyph_telemetry = stub_set_glyph_tel,
        .set_dwell_telemetry = stub_set_dwell_tel,
        .set_flag = stub_flag,
        .reset_counters = stub_reset,
        .send_identity = stub_identity,
        .ack = stub_ack,
        .note_command = stub_note,
        .host_takeover = stub_takeover,
    };
    commands_set_deps(&g_installed);
}

int main(void)
{
    fake_time_reset(0);
    install_stubs();

    feed_line("M sim");
    TEST_CHECK(g_mode == APP_MODE_SIM);
    TEST_CHECK(strstr(g_last_ack, "sim") != NULL);
    TEST_CHECK_EQ_INT(g_cmd_ok, 1);

    feed_line("M pov");
    TEST_CHECK(g_mode == APP_MODE_POV);

    feed_line("M static");
    TEST_CHECK(g_mode == APP_MODE_STATIC);

    feed_line("M nope");
    TEST_CHECK_EQ_INT(g_cmd_err, 1);

    feed_line("V 0");
    TEST_CHECK_EQ_INT(g_volume, 0);
    feed_line("V 2");
    TEST_CHECK_EQ_INT(g_volume, 2);
    feed_line("V 9");
    TEST_CHECK_EQ_INT(g_cmd_err, 2);

    feed_line("?");
    TEST_CHECK(strstr(g_last_ack, "mode=") != NULL);

    feed_line("S 2 3");
    TEST_CHECK_EQ_INT(g_score_home, 2);
    TEST_CHECK_EQ_INT(g_score_away, 3);

    /* Single pixel: both coordinates parsed, ack names the GPIOs. */
    int err_before = g_cmd_err;
    feed_line("X 3 5");
    TEST_CHECK_EQ_INT(g_pixel_row, 3);
    TEST_CHECK_EQ_INT(g_pixel_col, 5);
    TEST_CHECK(strncmp(g_last_ack, "OK pixel r3 c5", 14) == 0);
    TEST_CHECK(strstr(g_last_ack, "row=GP") != NULL);
    TEST_CHECK(strstr(g_last_ack, "col=GP") != NULL);
    feed_line("X 0 0");
    TEST_CHECK_EQ_INT(g_pixel_row, 0);
    TEST_CHECK_EQ_INT(g_pixel_col, 0);
    feed_line("X 7 7");
    TEST_CHECK_EQ_INT(g_pixel_row, 7);
    TEST_CHECK_EQ_INT(g_pixel_col, 7);

    /* Rejected without touching the display. */
    feed_line("X 8 0");
    feed_line("X 0 8");
    feed_line("X 3");
    feed_line("X");
    TEST_CHECK_EQ_INT(g_cmd_err, err_before + 4);
    TEST_CHECK_EQ_INT(g_pixel_row, 7);
    TEST_CHECK_EQ_INT(g_pixel_col, 7);
    TEST_CHECK(strncmp(g_last_ack, "ERR pixel", 9) == 0);

    /* Display commands take the display over from the boot demo, before they
     * run (checked against the handler's first dep call); queries and tuning
     * leave it alone, as do unknown verbs. */
    static const struct {
        const char *line;
        int *handler_at;
    } kTakeovers[] = {
        {"X 1 2", &g_pixel_at},  {"G 2", &g_glyph_at},     {"B", &g_clear_at},
        {"S 1 1", &g_score_at},  {"V 0", &g_volume_at},    {"M static", &g_mode_at},
        {"P", &g_pause_at},      {"P", &g_pause_at},
    };
    for (size_t i = 0; i < sizeof(kTakeovers) / sizeof(kTakeovers[0]); i++) {
        int before = g_takeover_count;
        feed_line(kTakeovers[i].line);
        TEST_CHECK_EQ_INT(g_takeover_count, before + 1);
        TEST_CHECK(g_takeover_at < *kTakeovers[i].handler_at);
    }
    /* A rejected display command still takes over: the host wants the display. */
    int takeovers = g_takeover_count;
    feed_line("X 9 9");
    TEST_CHECK_EQ_INT(g_takeover_count, takeovers + 1);
    static const char *const kNoTakeover[] = {"I", "?", "D 400", "H", "Z", "Q"};
    for (size_t i = 0; i < sizeof(kNoTakeover) / sizeof(kNoTakeover[0]); i++) {
        feed_line(kNoTakeover[i]);
    }
    TEST_CHECK_EQ_INT(g_takeover_count, takeovers + 1);

    /* The hook is optional. */
    CommandsDeps no_hook = g_installed;
    no_hook.host_takeover = NULL;
    commands_set_deps(&no_hook);
    feed_line("G 3");
    TEST_CHECK_EQ_INT(g_glyph, 3);
    commands_set_deps(&g_installed);

    /* Idle line reset: partial command, wait, then new command. */
    fake_time_set(0);
    commands_feed_byte('M');
    fake_time_advance(300000ull);
    feed_line("G 1");
    TEST_CHECK_EQ_INT(g_glyph, 1);

    return test_finish("commands");
}
