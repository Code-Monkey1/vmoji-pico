#include "test_harness.h"

#include "boot_demo.h"
#include "led-matrix.h"

#define FRAME_US 500000ull

static int g_row = -1;
static int g_col = -1;
static int g_draws;
static int g_clears;

static void stub_draw_pixel(int row, int col)
{
    g_row = row;
    g_col = col;
    g_draws++;
}

static void stub_clear(void)
{
    g_clears++;
}

static const BootDemoDisplay kDisplay = {
    .draw_pixel = stub_draw_pixel,
    .clear = stub_clear,
};

/* Every test starts from a stopped demo and fresh counters, so tests do not
 * depend on each other's order (the module keeps its state in statics). */
static void reset_stubs(void)
{
    boot_demo_stop();
    g_row = -1;
    g_col = -1;
    g_draws = 0;
    g_clears = 0;
}

static void test_pixel_walk_order_and_wrap(void)
{
    reset_stubs();
    uint64_t t = 1000;
    boot_demo_start(BOOT_DEMO_PIXEL_WALK, &kDisplay, t);
    TEST_CHECK(boot_demo_running());
    TEST_CHECK_EQ_INT(g_draws, 1);
    TEST_CHECK_EQ_INT(g_row, 0);
    TEST_CHECK_EQ_INT(g_col, 0);

    /* Not due yet. */
    boot_demo_service(t + FRAME_US - 1);
    TEST_CHECK_EQ_INT(g_draws, 1);

    /* Row-major, every pixel once, then back to r0 c0. */
    for (int i = 1; i <= NB_ROW * NB_COL; i++) {
        t += FRAME_US;
        boot_demo_service(t);
        int expect = i % (NB_ROW * NB_COL);
        TEST_CHECK_EQ_INT(g_row, expect / NB_COL);
        TEST_CHECK_EQ_INT(g_col, expect % NB_COL);
    }
    TEST_CHECK_EQ_INT(g_draws, 1 + NB_ROW * NB_COL);
    TEST_CHECK_EQ_INT(g_clears, 0);
    boot_demo_stop();
}

static void test_late_service_advances_one_frame(void)
{
    reset_stubs();
    boot_demo_start(BOOT_DEMO_PIXEL_WALK, &kDisplay, 0);
    uint64_t late = 10 * FRAME_US;
    boot_demo_service(late);
    TEST_CHECK_EQ_INT(g_draws, 2);
    TEST_CHECK_EQ_INT(g_col, 1);
    /* Rescheduled from the late pass, not from the missed deadlines. */
    boot_demo_service(late + FRAME_US - 1);
    TEST_CHECK_EQ_INT(g_draws, 2);
    boot_demo_service(late + FRAME_US);
    TEST_CHECK_EQ_INT(g_col, 2);
    boot_demo_stop();
}

static void test_stop_clears_once_and_stays_stopped(void)
{
    reset_stubs();
    boot_demo_start(BOOT_DEMO_PIXEL_WALK, &kDisplay, 0);
    boot_demo_stop();
    TEST_CHECK(!boot_demo_running());
    TEST_CHECK_EQ_INT(g_clears, 1);

    int draws = g_draws;
    boot_demo_service(100 * FRAME_US);
    TEST_CHECK_EQ_INT(g_draws, draws);

    /* The host's later display commands must not keep wiping the matrix. */
    boot_demo_stop();
    TEST_CHECK_EQ_INT(g_clears, 1);
}

static void test_none_and_bad_input_never_draw(void)
{
    reset_stubs();
    boot_demo_start(BOOT_DEMO_NONE, &kDisplay, 0);
    TEST_CHECK(!boot_demo_running());
    boot_demo_start(BOOT_DEMO_COUNT, &kDisplay, 0);
    TEST_CHECK(!boot_demo_running());
    boot_demo_start(BOOT_DEMO_PIXEL_WALK, NULL, 0);
    TEST_CHECK(!boot_demo_running());

    boot_demo_service(10 * FRAME_US);
    boot_demo_stop();
    TEST_CHECK_EQ_INT(g_draws, 0);
    TEST_CHECK_EQ_INT(g_clears, 0);
}

static void test_restart_stops_the_running_demo(void)
{
    reset_stubs();
    boot_demo_start(BOOT_DEMO_PIXEL_WALK, &kDisplay, 0);
    boot_demo_service(FRAME_US);
    TEST_CHECK_EQ_INT(g_col, 1);

    /* Restarting begins again at r0 c0, after clearing the old frame. */
    boot_demo_start(BOOT_DEMO_PIXEL_WALK, &kDisplay, 2 * FRAME_US);
    TEST_CHECK_EQ_INT(g_clears, 1);
    TEST_CHECK_EQ_INT(g_row, 0);
    TEST_CHECK_EQ_INT(g_col, 0);

    /* A failed start must not leave the old frame lit with no way to clear it. */
    boot_demo_start(BOOT_DEMO_NONE, &kDisplay, 3 * FRAME_US);
    TEST_CHECK(!boot_demo_running());
    TEST_CHECK_EQ_INT(g_clears, 2);
}

int main(void)
{
    test_pixel_walk_order_and_wrap();
    test_late_service_advances_one_frame();
    test_stop_clears_once_and_stays_stopped();
    test_none_and_bad_input_never_draw();
    test_restart_stops_the_running_demo();
    return test_finish("boot_demo");
}
