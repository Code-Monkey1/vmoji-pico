#include "boot_demo.h"

#include <stddef.h>

#include "led-matrix.h"

/* Slow enough to spot a dark or dim LED as the walk goes by (one pass of 64
 * LEDs in 32 s). Not faster than the 2 Hz framebuffer telemetry
 * (kFrameBufIntervalUs in telemetry.cpp), or the dashboard's matrix mirror
 * samples every other frame and seems to skip half the LEDs. */
#define PIXEL_WALK_FRAME_US 500000u

/** One animation: `render` draws frame `frame` (0 .. frame_count - 1). */
typedef struct {
    uint32_t frame_us;
    uint16_t frame_count;
    void (*render)(uint16_t frame, const BootDemoDisplay *display);
} BootDemoAnimation;

static void render_pixel_walk(uint16_t frame, const BootDemoDisplay *display)
{
    /* Row-major from r0 c0, matching walk_order() in tools/dashboard/pixel_walk.py. */
    display->draw_pixel(frame / NB_COL, frame % NB_COL);
}

/* Indexed by BootDemoId. A new animation is an enum value, a render function
 * and a row here; frame_count == 0 marks "nothing to play". */
static const BootDemoAnimation kAnimations[] = {
    [BOOT_DEMO_NONE] = {0, 0, NULL},
    [BOOT_DEMO_PIXEL_WALK] = {PIXEL_WALK_FRAME_US, NB_ROW * NB_COL, render_pixel_walk},
};

_Static_assert(sizeof(kAnimations) / sizeof(kAnimations[0]) == BOOT_DEMO_COUNT,
               "every BootDemoId needs a row in kAnimations");

static const BootDemoAnimation *g_anim;
static const BootDemoDisplay *g_display;
static uint16_t g_frame;
static uint64_t g_next_frame_us;

static void show_frame(uint64_t now_us)
{
    g_anim->render(g_frame, g_display);
    g_next_frame_us = now_us + g_anim->frame_us;
}

void boot_demo_start(BootDemoId id, const BootDemoDisplay *display, uint64_t now_us)
{
    boot_demo_stop();
    if ((unsigned)id >= BOOT_DEMO_COUNT || display == NULL ||
        kAnimations[id].frame_count == 0) {
        return;
    }
    g_anim = &kAnimations[id];
    g_display = display;
    g_frame = 0;
    show_frame(now_us);
}

void boot_demo_service(uint64_t now_us)
{
    if (g_anim == NULL || now_us < g_next_frame_us) {
        return;
    }
    g_frame = (uint16_t)((g_frame + 1u) % g_anim->frame_count);
    /* Rescheduled from now, not from the missed deadline: after a long stall
     * the walk simply resumes instead of racing through the frames it missed. */
    show_frame(now_us);
}

void boot_demo_stop(void)
{
    if (g_anim == NULL) {
        return;
    }
    g_anim = NULL;
    g_display->clear();
}

bool boot_demo_running(void)
{
    return g_anim != NULL;
}
