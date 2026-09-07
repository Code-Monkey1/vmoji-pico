#include "test_harness.h"

#include "rotation_estimator.h"
#include "rotation_sync.h"

int main(void)
{
    RotationEstimator e;
    rotation_estimator_init(&e, ROTATION_SIM_PERIOD_US);

    rotation_estimator_note_edge(&e, 1000000ull);
    TEST_CHECK(e.sync_ok);
    TEST_CHECK_EQ_U32(e.rev_count, 1);
    TEST_CHECK_EQ_U32(e.period_us, ROTATION_SIM_PERIOD_US);

    rotation_estimator_note_edge(&e, 1000000ull + 60000ull);
    TEST_CHECK_EQ_U32(e.rev_count, 2);
    /* EMA: (60000*3 + 60000)/4 after first sample replaces? first sample sets
     * from previous default: (60000*3+60000)/4 = 60000 */
    TEST_CHECK_EQ_U32(e.period_us, 60000u);
    TEST_CHECK_EQ_U32(rotation_estimator_rpm(&e), 1000u);

    /* Bounce < 5 ms ignored for EMA but still counts edge. */
    uint32_t before = e.period_us;
    rotation_estimator_note_edge(&e, e.last_edge_us + 1000ull);
    TEST_CHECK_EQ_U32(e.period_us, before);

    /* Sync loss */
    e.sim = false;
    TEST_CHECK(rotation_estimator_check_loss(&e, e.last_edge_us + 300000ull));
    TEST_CHECK(!e.sync_ok);

    /* Sticky: a second check while still timed out does not re-fire. */
    TEST_CHECK(!rotation_estimator_check_loss(&e, e.last_edge_us + 400000ull));

    return test_finish("rotation_estimator");
}
