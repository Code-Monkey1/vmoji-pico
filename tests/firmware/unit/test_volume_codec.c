#include "test_harness.h"

#include "volume.h"
#include "volume_codec.h"

#include <stdint.h>
#include <string.h>

/* Canonical test map: cols GP0-7, rows GP8-15. */
static const uint8_t kCols[8] = {0, 1, 2, 3, 4, 5, 6, 7};
static const uint8_t kRows[8] = {8, 9, 10, 11, 12, 13, 14, 15};

static uint32_t weight_sum(void)
{
    uint32_t s = 0;
    for (int c = 0; c < 8; c++) {
        s += volume_codec_col_weight(c);
    }
    return s;
}

int main(void)
{
    volume_codec_init_pins(kCols, kRows);

    TEST_CHECK_EQ_U32(CODEC_STEPS_PER_REV, 768);
    TEST_CHECK_EQ_U32(weight_sum(), CODEC_WEIGHT_SUM);

    VolumeFrame empty;
    volume_clear(&empty);
    VolumeScanlist list;
    volume_codec_bake(&empty, &list);

    uint32_t all_rows = 0;
    for (int r = 0; r < 8; r++) {
        all_rows |= (1u << kRows[r]);
    }
    TEST_CHECK_EQ_U32(list.blank, all_rows);
    for (uint32_t i = 0; i < CODEC_STEPS_PER_REV; i++) {
        /* Empty: each step still selects some column anode, cathodes all high. */
        TEST_CHECK((list.steps[i] & all_rows) == all_rows);
    }

    VolumeFrame one;
    volume_clear(&one);
    const int theta = 3;
    const int col = 0;
    const int row = 2;
    volume_set(&one, theta, col, row, true);
    volume_codec_bake(&one, &list);

    uint8_t w = volume_codec_col_weight(col);
    /* Steps for slice theta start after theta * 32. */
    size_t base = (size_t)theta * CODEC_WEIGHT_SUM;
    uint32_t expected = all_rows | (1u << kCols[col]);
    expected &= ~(1u << kRows[row]);

    for (uint8_t i = 0; i < w; i++) {
        TEST_CHECK_EQ_U32(list.steps[base + i], expected);
    }

    bool pixels[8][8];
    memset(pixels, 0, sizeof(pixels));
    pixels[1][3] = true;
    uint32_t rows_out[8];
    uint32_t blank;
    uint32_t mask;
    volume_codec_bake_static_rows(pixels, rows_out, &blank, &mask);
    TEST_CHECK_EQ_U32(blank, all_rows);
    uint32_t row1 = all_rows;
    row1 &= ~(1u << kRows[1]);
    row1 |= (1u << kCols[3]);
    TEST_CHECK_EQ_U32(rows_out[1], row1);

    return test_finish("volume_codec");
}
