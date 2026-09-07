#include "test_harness.h"

#include "fake_platform.h"
#include "pov_service.h"
#include "volume_codec.h"

#include <string.h>

static const uint8_t kCols[8] = {0, 1, 2, 3, 4, 5, 6, 7};
static const uint8_t kRows[8] = {8, 9, 10, 11, 12, 13, 14, 15};

int main(void)
{
    volume_codec_init_pins(kCols, kRows);

    FakePlatformState st;
    fake_platform_reset(&st);
    PovPlatform plat = fake_platform_make(&st);

    PovService svc;
    pov_service_init(&svc, &plat);

    RotationSnapshot snap = {
        .period_us = 60000,
        .rev_count = 1,
        .rpm = 1000,
        .sync_ok = true,
        .sim = true,
    };

    pov_service_set_mode(&svc, APP_MODE_SIM);
    fake_platform_push_rev(&st, &snap);
    pov_service_service(&svc);

    TEST_CHECK(pov_service_scan_busy(&svc));
    uint8_t busy = pov_service_busy_slot(&svc);
    uint8_t display = pov_service_display_list(&svc);
    TEST_CHECK_EQ_U32(busy, display);
    TEST_CHECK(st.last_list == pov_service_list(&svc, display));

    /* Poison the busy slot; rebake must write the other slot. */
    VolumeScanlist poison;
    memset(&poison, 0xA5, sizeof(poison));
    memcpy(&svc.lists[busy], &poison, sizeof(poison));

    pov_service_set_volume(&svc, 0);
    pov_service_request_rebake(&svc);
    int starts = st.start_count;
    pov_service_service(&svc);
    TEST_CHECK_EQ_INT(st.start_count, starts);

    uint8_t new_display = pov_service_display_list(&svc);
    TEST_CHECK_EQ_U32(new_display, (uint8_t)(busy ^ 1u));

    TEST_CHECK(memcmp(&svc.lists[busy], &poison, sizeof(poison)) == 0);
    TEST_CHECK(memcmp(&svc.lists[new_display], &poison, sizeof(poison)) != 0);

    pov_service_release_scan(&svc);
    TEST_CHECK(!pov_service_scan_busy(&svc));

    return test_finish("busy_slot");
}
