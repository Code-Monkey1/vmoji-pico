#include "test_harness.h"

#include "scan_timing.h"
#include "volume_codec.h"

int main(void)
{
    uint32_t step = scan_timing_step_us(60000u, CODEC_STEPS_PER_REV);
    TEST_CHECK_EQ_U32(step, 60000u / CODEC_STEPS_PER_REV);

    TEST_CHECK_EQ_U32(scan_timing_step_us(100, CODEC_STEPS_PER_REV), 1u);

    uint32_t cycles = scan_timing_delay_cycles(78u, 125000000u);
    TEST_CHECK_EQ_U32(cycles, 9718u);

    /* With 5 µs settle, lit time is 73 µs → 73*125-32 = 9093. */
    uint32_t lit = scan_timing_lit_delay_cycles(78u, 5u, 125000000u);
    TEST_CHECK_EQ_U32(lit, 9093u);
    TEST_CHECK(lit < cycles);

    /* Settle >= step → minimal 1-cycle lit (via 1 µs path). */
    uint32_t tiny = scan_timing_lit_delay_cycles(5u, 5u, 125000000u);
    TEST_CHECK_EQ_U32(tiny, 1u);

    TEST_CHECK_EQ_U32(scan_timing_delay_cycles(0, 125000000u), 1u);

    return test_finish("scan_timing");
}
