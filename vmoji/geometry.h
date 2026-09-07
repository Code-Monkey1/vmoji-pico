// Maps logical voxels (r, theta, z) onto the physical 8x8 matrix.
//
// Default: candle-like diameter span — columns straddle the spin axis
// (±radius), rows are height. Swap this adapter later for an offset mount
// without touching the scanner or codec call sites.

#ifndef VMOJI_GEOMETRY_H
#define VMOJI_GEOMETRY_H

#include <stdint.h>

#include "led-matrix.h"

#ifdef __cplusplus
extern "C" {
#endif

/** Angular slices per revolution (software division of the IR index). */
#ifndef ANGULAR_SLICES
#define ANGULAR_SLICES 24
#endif

/**
 * Column index 0..7 → signed radius about the axis.
 * Layout: c0=-4 … c3=-1, c4=+1 … c7=+4 (no zero column; both halves lit).
 */
static inline int geometry_col_to_radius(int col)
{
    if (col < 4) {
        return col - 4;
    }
    return col - 3;
}

/** Absolute radius 1..4 for dwell weighting. */
static inline int geometry_col_abs_radius(int col)
{
    int r = geometry_col_to_radius(col);
    return r < 0 ? -r : r;
}

/** Row index 0..7 → height z (identity for the prototype panel). */
static inline int geometry_row_to_z(int row)
{
    return row;
}

static inline int geometry_z_to_row(int z)
{
    return z;
}

/** Radius 1..4 → column on the positive side (right half). */
static inline int geometry_radius_to_col_pos(int abs_r)
{
    return 3 + abs_r;
}

/** Radius 1..4 → column on the negative side (left half). */
static inline int geometry_radius_to_col_neg(int abs_r)
{
    return 4 - abs_r;
}

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_GEOMETRY_H
