#ifndef VMOJI_FAKE_TIME_H
#define VMOJI_FAKE_TIME_H

#include <stdint.h>

void fake_time_reset(uint64_t start_us);
void fake_time_set(uint64_t now_us);
void fake_time_advance(uint64_t delta_us);
uint64_t fake_time_now_us(void);

#endif
