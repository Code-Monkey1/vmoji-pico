// Voxel frame → GPIO mask step list for one revolution.
//
// Each mux step is one uint32_t with matrix pin bits set for a single active
// column (anode) and the lit row cathodes cleared (driven low). Inactive
// cathodes are driven high. Radius weighting expands outer columns into more
// equal-timed steps so DMA/Core1 can pace at a fixed interval.

#ifndef VMOJI_VOLUME_CODEC_H
#define VMOJI_VOLUME_CODEC_H

#include <stddef.h>
#include <stdint.h>

#include "geometry.h"
#include "volume.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Mitxela-style relative weights per column (outer brighter / longer).
 * Integer duplicates: 7,5,3,1,1,3,5,7 → 32 steps per slice, 768 per rev.
 */
#define CODEC_WEIGHT_SUM 32
#define CODEC_STEPS_PER_REV (ANGULAR_SLICES * CODEC_WEIGHT_SUM)

typedef struct {
    uint32_t steps[CODEC_STEPS_PER_REV];
    uint32_t blank;  /* all matrix LEDs off */
    uint32_t pin_mask;
} VolumeScanlist;

void volume_codec_init(void);

/**
 * Initialise from an explicit pin map (host tests use a canonical layout).
 * cols/rows are GPIO numbers for the eight columns and eight rows.
 */
void volume_codec_init_pins(const uint8_t cols[NB_COL], const uint8_t rows[NB_ROW]);

/** Column weight used by the bake expansion (0 if col out of range). */
uint8_t volume_codec_col_weight(int col);

/** Bake one volume frame into a fixed-rate step list. */
void volume_codec_bake(const VolumeFrame *frame, VolumeScanlist *out);

/** Encode a single static 8x8 framebuffer as 8 row-mux masks (for static mode). */
void volume_codec_bake_static_rows(const bool pixels[NB_ROW][NB_COL],
                                   uint32_t out_rows[NB_ROW],
                                   uint32_t *blank,
                                   uint32_t *pin_mask);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_VOLUME_CODEC_H
