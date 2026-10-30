#include "test_harness.h"

#include "geometry.h"
#include "volumes_builtin.h"

#include <stdbool.h>

static int count_voxels(const VolumeFrame *f)
{
    int n = 0;
    for (int t = 0; t < ANGULAR_SLICES; t++) {
        for (int r = 0; r < NB_ROW; r++) {
            for (int c = 0; c < NB_COL; c++) {
                if (f->slice[t].voxel[r][c]) {
                    n++;
                }
            }
        }
    }
    return n;
}

static bool only_pos_radius(const VolumeFrame *f)
{
    for (int t = 0; t < ANGULAR_SLICES; t++) {
        for (int r = 0; r < NB_ROW; r++) {
            for (int c = 0; c < 4; c++) {
                if (f->slice[t].voxel[r][c]) {
                    return false;
                }
            }
        }
    }
    return true;
}

static bool only_theta0(const VolumeFrame *f)
{
    for (int t = 1; t < ANGULAR_SLICES; t++) {
        for (int r = 0; r < NB_ROW; r++) {
            for (int c = 0; c < NB_COL; c++) {
                if (f->slice[t].voxel[r][c]) {
                    return false;
                }
            }
        }
    }
    return true;
}

int main(void)
{
    VolumeFrame frame;

    volumes_builtin_draw(0, &frame);
    TEST_CHECK(count_voxels(&frame) > 20);

    volumes_builtin_draw(1, &frame);
    TEST_CHECK(count_voxels(&frame) > 5);
    TEST_CHECK(only_pos_radius(&frame));

    /* Upright L: lone marker in the top matrix row, foot one row above the
     * bottom, nothing from the foot in the top half. */
    const int marker_col = geometry_radius_to_col_pos(4);
    const int foot_col = geometry_radius_to_col_pos(2);
    TEST_CHECK(frame.slice[0].voxel[0][marker_col]);
    TEST_CHECK(frame.slice[0].voxel[NB_ROW - 2][foot_col]);
    TEST_CHECK(frame.slice[5].voxel[NB_ROW - 2][foot_col]);
    for (int row = 0; row < NB_ROW / 2; row++) {
        TEST_CHECK(!frame.slice[5].voxel[row][foot_col]);
    }

    volumes_builtin_draw(2, &frame);
    TEST_CHECK(count_voxels(&frame) > 0);
    TEST_CHECK(only_theta0(&frame));

    TEST_CHECK(volumes_builtin_name(1) != NULL);

    return test_finish("volumes_builtin");
}
