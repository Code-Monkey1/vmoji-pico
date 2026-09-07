#include "test_harness.h"

#include "volume.h"

int main(void)
{
    VolumeBuffer buf;
    volume_init(&buf);

    VolumeFrame *a = volume_inactive(&buf);
    volume_set(a, 0, 3, 2, true);
    TEST_CHECK(volume_get(a, 0, 3, 2));
    TEST_CHECK(!volume_get(volume_active(&buf), 0, 3, 2));

    volume_flip(&buf);
    TEST_CHECK(volume_get(volume_active(&buf), 0, 3, 2));

    VolumeFrame *b = volume_inactive(&buf);
    volume_clear(b);
    volume_set_radius(b, 5, 3, 4, true);
    TEST_CHECK(volume_get(b, 5, geometry_radius_to_col_pos(3), 4));
    TEST_CHECK(volume_get(b, 5, geometry_radius_to_col_neg(3), 4));

    volume_flip(&buf);
    TEST_CHECK(!volume_get(volume_active(&buf), 0, 3, 2));
    TEST_CHECK(volume_get(volume_active(&buf), 5, geometry_radius_to_col_pos(3), 4));

    return test_finish("volume");
}
