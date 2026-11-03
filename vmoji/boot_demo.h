// Boot demo: an animation the board loops on its own from power-up until the
// host takes over the display.
//
// A bring-up aid: with no host attached the matrix still shows that the board
// is powered and scanning. Which animation plays is one BootDemoId picked in
// main.c; the animations themselves are rows in a table in boot_demo.c, so
// adding one touches neither the main loop nor the command parser. The display
// is injected, which keeps this module free of the Pico SDK and host-testable.

#ifndef VMOJI_BOOT_DEMO_H
#define VMOJI_BOOT_DEMO_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    BOOT_DEMO_NONE = 0,   /**< Boot dark: nothing drawn until the host asks. */
    BOOT_DEMO_PIXEL_WALK, /**< Every LED alone, row by row (same order as the dashboard walk). */
    BOOT_DEMO_COUNT,
} BootDemoId;

/**
 * What an animation may draw with. Must outlive the demo (the pointer is kept).
 * Only what the pixel walk needs today: an animation that lights several pixels
 * at once adds its own op here (e.g. set_pixel) rather than bending draw_pixel.
 */
typedef struct {
    void (*draw_pixel)(int row, int col); /**< Clears the matrix, lights one pixel. */
    void (*clear)(void);
} BootDemoDisplay;

/**
 * Start looping animation `id`, drawing its first frame right away. Stops (and
 * clears) any demo already running first. BOOT_DEMO_NONE, an out-of-range id or
 * a NULL display leaves the demo stopped.
 */
void boot_demo_start(BootDemoId id, const BootDemoDisplay *display, uint64_t now_us);

/**
 * Advance one frame when it is due; call every main-loop pass. A late call
 * advances a single frame (no catch-up burst), and the animation wraps.
 */
void boot_demo_service(uint64_t now_us);

/**
 * The host took over the display: stop for good (until the next boot). Clears
 * the matrix if the demo was running, so the host's command draws on a clean
 * display; a no-op otherwise.
 */
void boot_demo_stop(void);

bool boot_demo_running(void);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_BOOT_DEMO_H
