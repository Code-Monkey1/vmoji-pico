#include "rotation_sync.h"

#include "board_pins.h"
#include "rotation_estimator.h"

#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "hardware/sync.h"
#include "pico/stdlib.h"
#include "pico/time.h"

static volatile uint64_t g_irq_edge_us;
static volatile bool g_irq_pending;

static RotationEstimator g_est;
static uint64_t g_sim_next_us;
static bool g_sync_lost_pending;

static void gpio_irq_handler(uint gpio, uint32_t events)
{
    (void)events;
    if (gpio != INDEX_IR_GPIO || g_est.sim) {
        return;
    }
    g_irq_edge_us = time_us_64();
    g_irq_pending = true;
}

void rotation_sync_init(void)
{
    rotation_estimator_init(&g_est, ROTATION_SIM_PERIOD_US);
    g_sim_next_us = 0;
    g_irq_pending = false;
    g_sync_lost_pending = false;

    gpio_init(INDEX_IR_GPIO);
    gpio_set_dir(INDEX_IR_GPIO, GPIO_IN);
    gpio_pull_up(INDEX_IR_GPIO);
    gpio_set_irq_enabled_with_callback(INDEX_IR_GPIO, GPIO_IRQ_EDGE_FALL, true,
                                       &gpio_irq_handler);
}

void rotation_sync_set_sim(bool enabled)
{
    rotation_estimator_set_sim(&g_est, enabled, ROTATION_SIM_PERIOD_US);
    g_irq_pending = false;
    g_sync_lost_pending = false;
    if (enabled) {
        g_sim_next_us = time_us_64() + ROTATION_SIM_PERIOD_US;
        gpio_set_irq_enabled(INDEX_IR_GPIO, GPIO_IRQ_EDGE_FALL, false);
    } else {
        gpio_set_irq_enabled(INDEX_IR_GPIO, GPIO_IRQ_EDGE_FALL, true);
    }
}

void rotation_sync_reset(void)
{
    uint32_t ints = save_and_disable_interrupts();
    rotation_estimator_reset(&g_est, ROTATION_SIM_PERIOD_US);
    g_irq_pending = false;
    g_sync_lost_pending = false;
    restore_interrupts(ints);
    if (g_est.sim) {
        g_sim_next_us = time_us_64() + ROTATION_SIM_PERIOD_US;
    }
}

void rotation_sync_service(void)
{
    if (!g_est.sim) {
        return;
    }
    uint64_t now = time_us_64();
    if (now >= g_sim_next_us) {
        g_irq_edge_us = now;
        g_irq_pending = true;
        g_sim_next_us += ROTATION_SIM_PERIOD_US;
        if (g_sim_next_us < now) {
            g_sim_next_us = now + ROTATION_SIM_PERIOD_US;
        }
    }
}

bool rotation_sync_take_rev(RotationSnapshot *out)
{
    if (!g_irq_pending) {
        if (rotation_estimator_check_loss(&g_est, time_us_64())) {
            g_sync_lost_pending = true;
        }
        return false;
    }

    uint32_t ints = save_and_disable_interrupts();
    uint64_t edge = g_irq_edge_us;
    g_irq_pending = false;
    restore_interrupts(ints);

    rotation_estimator_note_edge(&g_est, edge);
    g_sync_lost_pending = false;

    if (out) {
        *out = rotation_estimator_snapshot(&g_est);
    }
    return true;
}

bool rotation_sync_take_sync_lost(void)
{
    if (!g_sync_lost_pending) {
        /* Also evaluate loss here so callers that only poll lost still work. */
        if (!g_irq_pending &&
            rotation_estimator_check_loss(&g_est, time_us_64())) {
            g_sync_lost_pending = true;
        }
    }
    if (!g_sync_lost_pending) {
        return false;
    }
    g_sync_lost_pending = false;
    return true;
}

RotationSnapshot rotation_sync_snapshot(void)
{
    return rotation_estimator_snapshot(&g_est);
}
