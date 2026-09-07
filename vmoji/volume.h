// Polar voxel volume: the content model, with no GPIO knowledge.
//
// Double-buffered so core 0 can bake the next revolution while core 1 displays
// the active one. Flip only between revolutions.

#ifndef VMOJI_VOLUME_H
#define VMOJI_VOLUME_H

#include <stdbool.h>
#include <stdint.h>

#include "geometry.h"
#include "led-matrix.h"

#ifdef __cplusplus
extern "C" {
#endif

/** One angular slice: 8 rows x 8 cols of on/off voxels. */
typedef struct {
    bool voxel[NB_ROW][NB_COL];
} VolumeSlice;

typedef struct {
    VolumeSlice slice[ANGULAR_SLICES];
} VolumeFrame;

typedef struct {
    VolumeFrame frame[2];
    volatile uint8_t active;  /* 0 or 1: buffer core 1 is scanning */
} VolumeBuffer;

void volume_init(VolumeBuffer *buf);

VolumeFrame *volume_inactive(VolumeBuffer *buf);
const VolumeFrame *volume_active(const VolumeBuffer *buf);

/** Publish the inactive buffer as active. Call between revolutions only. */
void volume_flip(VolumeBuffer *buf);

void volume_clear(VolumeFrame *frame);

void volume_set(VolumeFrame *frame, int theta, int col, int row, bool on);
bool volume_get(const VolumeFrame *frame, int theta, int col, int row);

/**
 * Set both left and right columns for a given absolute radius (1..4) at (θ,z).
 * Diameter geometry helper for symmetric content.
 */
void volume_set_radius(VolumeFrame *frame, int theta, int abs_r, int z, bool on);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_VOLUME_H
