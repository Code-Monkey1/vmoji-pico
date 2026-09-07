#include "fake_time.h"

static uint64_t g_now_us;

void fake_time_reset(uint64_t start_us)
{
    g_now_us = start_us;
}

void fake_time_set(uint64_t now_us)
{
    g_now_us = now_us;
}

void fake_time_advance(uint64_t delta_us)
{
    g_now_us += delta_us;
}

uint64_t fake_time_now_us(void)
{
    return g_now_us;
}
