#include "rotation_sync.h"

#include "board_pins.h"

#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "hardware/sync.h"
#include "pico/stdlib.h"
#include "pico/time.h"

/* EMA: period = (period * 3 + sample) / 4 */
#define PERIOD_EMA_NUM 3u
#define PERIOD_EMA_DEN 4u

#define MIN_PERIOD_US 5000u     /* 12000 RPM ceiling — reject bounce */
#define MAX_PERIOD_US 500000u   /* 120 RPM floor */
#define SYNC_LOSS_US 250000u

static volatile uint64_t g_irq_edge_us;
static volatile bool g_irq_pending;

static bool g_sim;
static uint64_t g_sim_next_us;
static uint64_t g_last_edge_us;
static uint32_t g_period_us = ROTATION_SIM_PERIOD_US;
static uint32_t g_rev_count;
static bool g_sync_ok;

static uint16_t rpm_from_period(uint32_t period_us)
{
    if (period_us == 0) {
        return 0;
    }
    /* rpm = 60e6 / period_us */
    uint32_t rpm = 60000000u / period_us;
    return rpm > 0xFFFFu ? 0xFFFFu : (uint16_t)rpm;
}

static void note_edge(uint64_t now_us)
{
    if (g_last_edge_us != 0) {
        uint32_t sample = (uint32_t)(now_us - g_last_edge_us);
        if (sample >= MIN_PERIOD_US && sample <= MAX_PERIOD_US) {
            if (g_period_us == 0) {
                g_period_us = sample;
            } else {
                g_period_us = (g_period_us * PERIOD_EMA_NUM + sample) / PERIOD_EMA_DEN;
            }
        }
    }
    g_last_edge_us = now_us;
    g_rev_count++;
    g_sync_ok = true;
}

static void gpio_irq_handler(uint gpio, uint32_t events)
{
    (void)events;
    if (gpio != INDEX_IR_GPIO || g_sim) {
        return;
    }
    g_irq_edge_us = time_us_64();
    g_irq_pending = true;
}

void rotation_sync_init(void)
{
    g_sim = false;
    g_sim_next_us = 0;
    g_last_edge_us = 0;
    g_period_us = ROTATION_SIM_PERIOD_US;
    g_rev_count = 0;
    g_sync_ok = false;
    g_irq_pending = false;

    gpio_init(INDEX_IR_GPIO);
    gpio_set_dir(INDEX_IR_GPIO, GPIO_IN);
    gpio_pull_up(INDEX_IR_GPIO);
    gpio_set_irq_enabled_with_callback(INDEX_IR_GPIO, GPIO_IRQ_EDGE_FALL, true,
                                       &gpio_irq_handler);
}

void rotation_sync_set_sim(bool enabled)
{
    g_sim = enabled;
    g_sync_ok = false;
    g_last_edge_us = 0;
    g_irq_pending = false;
    if (enabled) {
        g_period_us = ROTATION_SIM_PERIOD_US;
        g_sim_next_us = time_us_64() + ROTATION_SIM_PERIOD_US;
        gpio_set_irq_enabled(INDEX_IR_GPIO, GPIO_IRQ_EDGE_FALL, false);
    } else {
        gpio_set_irq_enabled(INDEX_IR_GPIO, GPIO_IRQ_EDGE_FALL, true);
    }
}

void rotation_sync_reset(void)
{
    uint32_t ints = save_and_disable_interrupts();
    g_last_edge_us = 0;
    g_irq_pending = false;
    g_sync_ok = false;
    g_period_us = ROTATION_SIM_PERIOD_US;
    restore_interrupts(ints);
    if (g_sim) {
        g_sim_next_us = time_us_64() + ROTATION_SIM_PERIOD_US;
    }
}

void rotation_sync_service(void)
{
    if (!g_sim) {
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
        if (g_sync_ok && !g_sim) {
            uint64_t now = time_us_64();
            if (g_last_edge_us != 0 && (now - g_last_edge_us) > SYNC_LOSS_US) {
                g_sync_ok = false;
            }
        }
        return false;
    }

    uint32_t ints = save_and_disable_interrupts();
    uint64_t edge = g_irq_edge_us;
    g_irq_pending = false;
    restore_interrupts(ints);

    note_edge(edge);

    if (out) {
        out->period_us = g_period_us;
        out->rev_count = g_rev_count;
        out->rpm = rpm_from_period(g_period_us);
        out->sync_ok = g_sync_ok || g_sim;
        out->sim = g_sim;
    }
    return true;
}

RotationSnapshot rotation_sync_snapshot(void)
{
    RotationSnapshot s;
    s.period_us = g_period_us;
    s.rev_count = g_rev_count;
    s.rpm = rpm_from_period(g_period_us);
    s.sync_ok = g_sync_ok || g_sim;
    s.sim = g_sim;
    return s;
}
