#include "test_harness.h"

#include "fake_platform.h"
#include "fake_time.h"
#include "pov_service.h"
#include "rotation_estimator.h"
#include "rotation_sync.h"
#include "volume_codec.h"

static const uint8_t kCols[8] = {0, 1, 2, 3, 4, 5, 6, 7};
static const uint8_t kRows[8] = {8, 9, 10, 11, 12, 13, 14, 15};

static int scanlist_lit_steps(const VolumeScanlist *list)
{
    int n = 0;
    for (uint32_t i = 0; i < CODEC_STEPS_PER_REV; i++) {
        if ((list->steps[i] & list->blank) != list->blank) {
            n++;
        }
    }
    return n;
}

int main(void)
{
    volume_codec_init_pins(kCols, kRows);
    fake_time_reset(0);

    FakePlatformState st;
    fake_platform_reset(&st);
    PovPlatform plat = fake_platform_make(&st);

    PovService svc;
    pov_service_init(&svc, &plat);
    TEST_CHECK(pov_service_mode(&svc) == APP_MODE_STATIC);

    /* --- Sim path with queued rev --- */
    pov_service_set_volume(&svc, 1);
    pov_service_set_mode(&svc, APP_MODE_SIM);
    TEST_CHECK(st.sim);

    RotationSnapshot snap = {
        .period_us = 60000,
        .rev_count = 1,
        .rpm = 1000,
        .sync_ok = true,
        .sim = true,
    };
    fake_platform_push_rev(&st, &snap);
    pov_service_service(&svc);
    TEST_CHECK_EQ_INT(st.start_count, 1);
    TEST_CHECK_EQ_U32(st.last_period_us, 60000u);
    TEST_CHECK(scanlist_lit_steps(
                   pov_service_list(&svc, pov_service_display_list(&svc))) > 0);

    /* --- POV sync loss via real estimator + timeout (not a fake sync_ok) --- */
    fake_platform_use_estimator(&st, true);
    fake_time_set(1000000ull);
    pov_service_set_mode(&svc, APP_MODE_POV);
    TEST_CHECK(!st.sim);

    fake_platform_push_edge(&st, 1000000ull);
    pov_service_service(&svc);
    TEST_CHECK(st.start_count >= 2);
    TEST_CHECK(pov_service_display_active(&svc));

    fake_time_set(1000000ull + 60000ull);
    fake_platform_push_edge(&st, fake_time_now_us());
    pov_service_service(&svc);
    TEST_CHECK(pov_service_display_active(&svc));

    /* No more edges; advance past sync-loss window. */
    fake_time_advance(ROT_EST_SYNC_LOSS_US + 1ull);
    int blanks_before = st.blank_count;
    int stops_before = st.stop_count;
    pov_service_service(&svc);
    TEST_CHECK(st.blank_count > blanks_before);
    TEST_CHECK(st.stop_count > stops_before);
    TEST_CHECK(!pov_service_display_active(&svc));

    /* Recover: new edge restarts display. */
    fake_platform_push_edge(&st, fake_time_now_us());
    int starts = st.start_count;
    pov_service_service(&svc);
    TEST_CHECK(st.start_count > starts);
    TEST_CHECK(pov_service_display_active(&svc));

    return test_finish("pov_service");
}
