// Shared helpers for motor-collet / motor-base / motor-base-lid.
// Include BOSL2 before this file. Mating defaults live in each print file's Customizer
// and must stay in sync (see comments on ring_id / flange_bolt_r / etc).

function mb_clearance_hole_d(screw_spec) =
    struct_val(screw_info(screw_spec), "diameter") + 0.4 + 2 * $slop;

function mb_nut_circum_d(screw_spec) =
    struct_val(nut_info(screw_spec), "width") / cos(30);

function mb_nut_pocket_d(screw_spec, extra_d = 0) =
    mb_nut_circum_d(screw_spec) + extra_d + 2 * $slop;

function mb_collet_od(motor_d, wall) =
    motor_d + 2 * wall;

// Flange bolt angles: first at +Y so the +X slit/key sector stays clear.
function mb_flange_bolt_angles(n) =
    [for (i = [0:n - 1]) 90 + i * 360 / n];

// Keyed flange 2D profile (XY). Key tab points +X (toward porch).
module mb_flange_profile(flange_od, key_w, key_d) {
    union() {
        circle(d = flange_od);
        right(flange_od / 2)
            square([key_d * 2, key_w], center = true);
    }
}

module mb_flange_solid(flange_od, flange_h, key_w, key_d) {
    linear_extrude(height = flange_h)
        mb_flange_profile(flange_od, key_w, key_d);
}
