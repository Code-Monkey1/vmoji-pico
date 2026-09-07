#include "volume_codec.h"

#include "board_pins.h"

#include <string.h>

/* Relative on-time per column index 0..7 (must sum to CODEC_WEIGHT_SUM). */
static const uint8_t kColWeight[NB_COL] = {7, 5, 3, 1, 1, 3, 5, 7};

static uint32_t col_bit[NB_COL];
static uint32_t row_bit[NB_ROW];
static uint32_t all_row_bits;
static uint32_t pin_mask;
static uint32_t blank_word;
static bool ready;

void volume_codec_init(void)
{
    const uint8_t *cols = board_col_pins();
    const uint8_t *rows = board_row_pins();
    pin_mask = 0;
    all_row_bits = 0;
    for (int c = 0; c < NB_COL; c++) {
        col_bit[c] = 1u << cols[c];
        pin_mask |= col_bit[c];
    }
    for (int r = 0; r < NB_ROW; r++) {
        row_bit[r] = 1u << rows[r];
        pin_mask |= row_bit[r];
        all_row_bits |= row_bit[r];
    }
    /* Columns off (0), cathodes inactive high — no LED path. */
    blank_word = all_row_bits;
    ready = true;
}

/**
 * One column dwell: that anode high, lit cathodes low, other cathodes high,
 * other anodes low.
 */
static uint32_t encode_column(const bool row_on[NB_ROW], int col)
{
    uint32_t word = all_row_bits;  /* start with all cathodes high (off) */
    word |= col_bit[col];          /* this anode on */
    for (int r = 0; r < NB_ROW; r++) {
        if (row_on[r]) {
            word &= ~row_bit[r];   /* sink lit rows */
        }
    }
    return word;
}

void volume_codec_bake(const VolumeFrame *frame, VolumeScanlist *out)
{
    if (!ready) {
        volume_codec_init();
    }
    out->pin_mask = pin_mask;
    out->blank = blank_word;

    size_t idx = 0;
    for (int theta = 0; theta < ANGULAR_SLICES; theta++) {
        for (int col = 0; col < NB_COL; col++) {
            bool rows[NB_ROW];
            for (int r = 0; r < NB_ROW; r++) {
                rows[r] = frame->slice[theta].voxel[r][col];
            }
            uint32_t word = encode_column(rows, col);
            for (uint8_t w = 0; w < kColWeight[col]; w++) {
                out->steps[idx++] = word;
            }
        }
    }
}

void volume_codec_bake_static_rows(const bool pixels[NB_ROW][NB_COL],
                                   uint32_t out_rows[NB_ROW],
                                   uint32_t *blank,
                                   uint32_t *out_mask)
{
    if (!ready) {
        volume_codec_init();
    }
    *blank = blank_word;
    *out_mask = pin_mask;

    for (int r = 0; r < NB_ROW; r++) {
        /* Row-mux static path: one cathode low, anodes from the row bits. */
        uint32_t word = all_row_bits;
        word &= ~row_bit[r];
        for (int c = 0; c < NB_COL; c++) {
            if (pixels[r][c]) {
                word |= col_bit[c];
            }
        }
        out_rows[r] = word;
    }
}
