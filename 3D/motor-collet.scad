include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <motor-base-common.scad>


/* [Motor] */
// RF-300C-like can diameter (mm).
motor_d = 24; // [20:0.1:40]
// Can height excluding shaft (mm).
motor_h = 12; // [8:0.5:40]


/* [Collet] */
collet_wall = 4.5; // [2:0.5:6]
// Must match motor-base pocket.
collet_flange_od = 48; // [30:0.5:60]
collet_flange_h = 3; // [2:0.5:6]
flange_bolt_r = 20; // [10:0.5:28]
flange_bolt_count = 3; // [3:1:6]
key_w = 8; // [4:0.5:16]
key_d = 2.5; // [1:0.5:6]
wire_slot_w = 4; // [2:0.5:10]
wire_slot_h = 5; // [3:0.5:10]


/* [Clamp] */
clamp_screw = "M3";
slit_width = 0.5; // [0.2:0.05:2]
clamp_offset = 14.5; // [8:0.1:25]
nut_trap_depth = 2.7; // [2:0.1:8]
teardrop_clamp_hole = true; // [true, false]
min_bore_to_clamp = 0.8; // [0.3:0.1:2]


/* [Hardware] */
mount_screw = "M3";


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_collet(
    motor_d = motor_d,
    motor_h = motor_h,
    collet_wall = collet_wall,
    collet_flange_od = collet_flange_od,
    collet_flange_h = collet_flange_h,
    flange_bolt_r = flange_bolt_r,
    flange_bolt_count = flange_bolt_count,
    key_w = key_w,
    key_d = key_d,
    wire_slot_w = wire_slot_w,
    wire_slot_h = wire_slot_h,
    clamp_screw = clamp_screw,
    slit_width = slit_width,
    clamp_offset = clamp_offset,
    nut_trap_depth = nut_trap_depth,
    teardrop_clamp_hole = teardrop_clamp_hole,
    min_bore_to_clamp = min_bore_to_clamp,
    mount_screw = mount_screw
) {
    eps = cut_overlap;
    bore_d = motor_d + $slop;
    od = mb_collet_od(motor_d, collet_wall);
    r = od / 2;
    screw_d = struct_val(screw_info(clamp_screw), "diameter");
    jaw_half = sqrt(max(0.01, r * r - clamp_offset * clamp_offset));
    clamp_hole_l = 2 * jaw_half + 2;
    bolt_angles = mb_flange_bolt_angles(flange_bolt_count);
    mount_hole_d = mb_clearance_hole_d(mount_screw);

    assert(clamp_offset + screw_d / 2 < r,
        "clamp_offset places the screw outside the collet");
    assert(clamp_offset - screw_d / 2 > bore_d / 2 + min_bore_to_clamp,
        "clamp_offset is too close to the motor bore");
    assert(collet_flange_od > od,
        "collet_flange_od must exceed collet barrel OD");
    assert(flange_bolt_r + mount_hole_d / 2 < collet_flange_od / 2 - 1,
        "flange bolts are too close to the flange rim");
    assert(flange_bolt_r - mount_hole_d / 2 > od / 2 + 0.5,
        "flange bolts collide with the collet barrel");
    assert(collet_flange_h < motor_h,
        "flange thicker than motor height");
    assert(wire_slot_h <= motor_h,
        "wire_slot_h exceeds motor height");

    diff() {
        union() {
            cyl(d = od, h = motor_h, anchor = BOTTOM);

            mb_flange_solid(
                collet_flange_od,
                collet_flange_h,
                key_w,
                key_d
            );
        }

        tag("remove") {
            down(eps / 2)
                cyl(d = bore_d, h = motor_h + eps, anchor = BOTTOM);

            // Clamp slit along +X (toward porch / wire exit).
            down(eps / 2)
                left(eps)
                    cuboid(
                        [od / 2 + key_d + 1 + eps, slit_width, motor_h + eps],
                        anchor = LEFT + BOTTOM
                    );

            up(motor_h / 2)
                right(clamp_offset)
                    screw_hole(
                        clamp_screw,
                        l = clamp_hole_l,
                        teardrop = teardrop_clamp_hole,
                        orient = FWD
                    )
                        position(BOT)
                            nut_trap_inline(
                                l = nut_trap_depth + eps,
                                spec = clamp_screw,
                                anchor = BOT
                            );

            up(wire_slot_h / 2 - eps / 2)
                right(bore_d / 4)
                    cuboid(
                        [
                            od / 2 + key_d + 2,
                            wire_slot_w,
                            wire_slot_h + eps
                        ],
                        anchor = LEFT + CENTER
                    );

            for (a = bolt_angles)
                zrot(a)
                    right(flange_bolt_r)
                        down(eps / 2)
                            cyl(
                                d = mount_hole_d,
                                h = collet_flange_h + eps,
                                anchor = BOTTOM
                            );
        }
    }
}


motor_collet();
