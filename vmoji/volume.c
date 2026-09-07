#include "volume.h"

#include <string.h>

void volume_init(VolumeBuffer *buf)
{
    memset(buf, 0, sizeof(*buf));
    buf->active = 0;
}

VolumeFrame *volume_inactive(VolumeBuffer *buf)
{
    return &buf->frame[buf->active ^ 1u];
}

const VolumeFrame *volume_active(const VolumeBuffer *buf)
{
    return &buf->frame[buf->active];
}

void volume_flip(VolumeBuffer *buf)
{
    buf->active ^= 1u;
}

void volume_clear(VolumeFrame *frame)
{
    memset(frame, 0, sizeof(*frame));
}

void volume_set(VolumeFrame *frame, int theta, int col, int row, bool on)
{
    if (theta < 0 || theta >= ANGULAR_SLICES) {
        return;
    }
    if (col < 0 || col >= NB_COL || row < 0 || row >= NB_ROW) {
        return;
    }
    frame->slice[theta].voxel[row][col] = on;
}

bool volume_get(const VolumeFrame *frame, int theta, int col, int row)
{
    if (theta < 0 || theta >= ANGULAR_SLICES) {
        return false;
    }
    if (col < 0 || col >= NB_COL || row < 0 || row >= NB_ROW) {
        return false;
    }
    return frame->slice[theta].voxel[row][col];
}

void volume_set_radius(VolumeFrame *frame, int theta, int abs_r, int z, bool on)
{
    if (abs_r < 1 || abs_r > 4) {
        return;
    }
    int row = geometry_z_to_row(z);
    volume_set(frame, theta, geometry_radius_to_col_neg(abs_r), row, on);
    volume_set(frame, theta, geometry_radius_to_col_pos(abs_r), row, on);
}
