#include "test_harness.h"

#include "geometry.h"

#include <stdint.h>

int main(void)
{
    TEST_CHECK_EQ_INT(geometry_col_to_radius(0), -4);
    TEST_CHECK_EQ_INT(geometry_col_to_radius(3), -1);
    TEST_CHECK_EQ_INT(geometry_col_to_radius(4), 1);
    TEST_CHECK_EQ_INT(geometry_col_to_radius(7), 4);

    for (int r = 1; r <= 4; r++) {
        TEST_CHECK_EQ_INT(geometry_col_abs_radius(geometry_radius_to_col_pos(r)),
                          r);
        TEST_CHECK_EQ_INT(geometry_col_abs_radius(geometry_radius_to_col_neg(r)),
                          r);
    }

    TEST_CHECK_EQ_INT(geometry_row_to_z(5), 5);
    TEST_CHECK_EQ_INT(geometry_z_to_row(2), 2);

    return test_finish("geometry");
}
