#ifndef VMOJI_VOLUMES_BUILTIN_H
#define VMOJI_VOLUMES_BUILTIN_H

#include "volume.h"

#ifdef __cplusplus
extern "C" {
#endif

#define BUILTIN_VOLUME_COUNT 3

/** 0 wireframe cube, 1 asymmetric L, 2 index bar at θ=0. */
void volumes_builtin_draw(int id, VolumeFrame *frame);

const char *volumes_builtin_name(int id);

#ifdef __cplusplus
}
#endif

#endif  // VMOJI_VOLUMES_BUILTIN_H
