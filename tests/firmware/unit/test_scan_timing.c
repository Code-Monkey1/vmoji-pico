#include "test_harness.h"

#include "scan_timing.h"
#include "volume_codec.h"

int main(void)
{
    uint32_t step = scan_timing_step_us(60000u, CODEC_STEPS_PER_REV);
    TEST_CHECK_EQ_U32(step, 60000u / CODEC_STEPS_PER_REV); /* 78 */

    TEST_CHECK_EQ_U32(scan_timing_step_us(100, CODEC_STEPS_PER_REV), 1u);
    TEST_CHECK_EQ_U32(scan_timing_step_us(0, 10), 1u);

    uint32_t cycles = scan_timing_delay_cycles(78u, 125000000u);
    /* 78 * 125 = 9750, minus 32 = 9718 */
    TEST_CHECK_EQ_U32(cycles, 9718u);

    TEST_CHECK_EQ_U32(scan_timing_delay_cycles(0, 125000000u), 1u);

    return test_finish("scan_timing");
}
