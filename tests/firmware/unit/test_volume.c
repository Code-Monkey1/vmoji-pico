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

    /* z is height: z=0 is stored in the bottom matrix row, the top z in row 0. */
    VolumeFrame *c = volume_inactive(&buf);
    volume_clear(c);
    volume_set(c, 0, 1, 0, true);
    volume_set(c, 0, 2, NB_ROW - 1, true);
    TEST_CHECK(c->slice[0].voxel[NB_ROW - 1][1]);
    TEST_CHECK(c->slice[0].voxel[0][2]);
    TEST_CHECK(!c->slice[0].voxel[0][1]);

    /* Out-of-range height is ignored, not wrapped. */
    volume_clear(c);
    volume_set(c, 0, 1, NB_ROW, true);
    volume_set(c, 0, 1, -1, true);
    TEST_CHECK(!volume_get(c, 0, 1, NB_ROW));
    for (int row = 0; row < NB_ROW; row++) {
        TEST_CHECK(!c->slice[0].voxel[row][1]);
    }

    return test_finish("volume");
}
