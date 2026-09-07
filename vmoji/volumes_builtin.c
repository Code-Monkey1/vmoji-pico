#include "volumes_builtin.h"

#include "geometry.h"

#include <string.h>

static void draw_wireframe_cube(VolumeFrame *frame)
{
    volume_clear(frame);
    /* Cube faces at a few angles; edges along r and z. */
    const int thetas[] = {0, 6, 12, 18};
    for (unsigned t = 0; t < sizeof(thetas) / sizeof(thetas[0]); t++) {
        int theta = thetas[t];
        for (int z = 1; z <= 6; z++) {
            volume_set_radius(frame, theta, 2, z, true);
            volume_set_radius(frame, theta, 4, z, true);
        }
        for (int r = 2; r <= 4; r++) {
            volume_set_radius(frame, theta, r, 1, true);
            volume_set_radius(frame, theta, r, 6, true);
        }
    }
    /* Horizontal edges connecting corners in θ. */
    for (int theta = 0; theta < ANGULAR_SLICES; theta++) {
        volume_set_radius(frame, theta, 4, 1, true);
        volume_set_radius(frame, theta, 4, 6, true);
    }
}

static void draw_asymmetric_l(VolumeFrame *frame)
{
    volume_clear(frame);
    /* Vertical stem near θ=0, only on the +radius side (orientation cue). */
    for (int z = 1; z <= 6; z++) {
        volume_set(frame, 0, geometry_radius_to_col_pos(3), z, true);
        volume_set(frame, 1, geometry_radius_to_col_pos(3), z, true);
    }
    /* Foot of the L along +θ at the bottom, still +radius only. */
    for (int theta = 0; theta <= 5; theta++) {
        volume_set(frame, theta, geometry_radius_to_col_pos(3), 1, true);
        volume_set(frame, theta, geometry_radius_to_col_pos(2), 1, true);
    }
    /* Small tip marker at high Z so up/down is obvious if inverted. */
    volume_set(frame, 0, geometry_radius_to_col_pos(4), 7, true);
}

static void draw_index_bar(VolumeFrame *frame)
{
    volume_clear(frame);
    for (int z = 0; z < NB_ROW; z++) {
        for (int r = 1; r <= 4; r++) {
            volume_set_radius(frame, 0, r, z, true);
        }
    }
}

void volumes_builtin_draw(int id, VolumeFrame *frame)
{
    switch (id) {
    case 0:
        draw_wireframe_cube(frame);
        break;
    case 1:
        draw_asymmetric_l(frame);
        break;
    case 2:
        draw_index_bar(frame);
        break;
    default:
        volume_clear(frame);
        break;
    }
}

const char *volumes_builtin_name(int id)
{
    switch (id) {
    case 0:
        return "cube";
    case 1:
        return "asym-L";
    case 2:
        return "index-bar";
    default:
        return "none";
    }
}
