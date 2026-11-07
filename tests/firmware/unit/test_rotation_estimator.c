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

    /* Hand speed (docs/bring-up.md): a gap past the sync-loss limit but within the period
     * limit drops sync between pulses, yet still moves the speed estimate. */
    RotationEstimator hand;
    rotation_estimator_init(&hand, ROTATION_SIM_PERIOD_US);
    uint64_t t = 1000000ull;
    const uint32_t medium_gap = (ROT_EST_SYNC_LOSS_US + ROT_EST_MAX_PERIOD_US) / 2u;
    for (int i = 0; i < 40; i++) {
        rotation_estimator_note_edge(&hand, t);
        TEST_CHECK(hand.sync_ok);
        TEST_CHECK(rotation_estimator_check_loss(&hand, t + ROT_EST_SYNC_LOSS_US + 1ull));
        t += medium_gap;
    }
    TEST_CHECK(hand.period_us > medium_gap - 10u && hand.period_us <= medium_gap);

    /* Slower than the period limit: sync still flashes on each pulse, but the estimate
     * ignores the gap, so rpm keeps its previous value. */
    uint32_t held = hand.period_us;
    t += ROT_EST_MAX_PERIOD_US + 1u;
    rotation_estimator_note_edge(&hand, t);
    TEST_CHECK(hand.sync_ok);
    TEST_CHECK_EQ_U32(hand.period_us, held);

    return test_finish("rotation_estimator");
}
