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

    volumes_builtin_draw(2, &frame);
    TEST_CHECK(count_voxels(&frame) > 0);
    TEST_CHECK(only_theta0(&frame));

    TEST_CHECK(volumes_builtin_name(1) != NULL);

    return test_finish("volumes_builtin");
}
