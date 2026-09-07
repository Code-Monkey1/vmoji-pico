include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <vmoji-mech-params.scad>
include <motor-base-common.scad>


/* [Lid] */
lid_t = 2.5; // [1.5:0.5:5]
lid_lip = 0.8; // [0:0.1:2]
lid_fit_slop = 0.25; // [0.1:0.05:0.8]
post_d = 8; // [6:0.5:14]
lid_screw = "M3";
teardrop_holes = true; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_base_lid(
    lid_t = lid_t,
    lid_lip = lid_lip,
    lid_fit_slop = lid_fit_slop,
    post_d = post_d,
    lid_screw = lid_screw,
    teardrop_holes = teardrop_holes
) {
    eps = cut_overlap;
    motor_y = mb_gear_center_dist();
    driven_od = mb_gear_outer_d(vm_driven_teeth);
    pinion_od = mb_gear_outer_d(vm_pinion_teeth);
    bearing_pocket_d = mb_bearing_pocket_d();

    layout = mb_layout(
        motor_y, vm_motor_d, vm_collet_flange_od, driven_od, pinion_od,
        vm_ring_od, bearing_pocket_d, vm_deck_margin, vm_wall_t
    );
    deck_half_x = mb_layout_get(layout, "deck_half_x");

    porch_x0 = deck_half_x - vm_wall_t;
    porch_outer_x = vm_porch_inner_x + 2 * vm_wall_t;
    porch_outer_y = vm_porch_inner_y + 2 * vm_wall_t;
    porch_x1 = porch_x0 + porch_outer_x;

    post_inset = vm_wall_t + post_d / 2 + 1;
    post_coords = [
        [porch_x0 + post_inset,  vm_porch_inner_y / 2 - post_d / 2 - 1],
        [porch_x0 + post_inset, -(vm_porch_inner_y / 2 - post_d / 2 - 1)],
        [porch_x1 - post_inset,  vm_porch_inner_y / 2 - post_d / 2 - 1],
        [porch_x1 - post_inset, -(vm_porch_inner_y / 2 - post_d / 2 - 1)]
    ];

    lip_x = vm_porch_inner_x - 2 * lid_fit_slop;
    lip_y = vm_porch_inner_y - 2 * lid_fit_slop;

    diff() {
        union() {
            right(porch_x0)
                cuboid(
                    [porch_outer_x, porch_outer_y, lid_t],
                    anchor = LEFT + BOTTOM,
                    chamfer = 1,
                    edges = [FRONT + RIGHT, BACK + RIGHT, FRONT + LEFT, BACK + LEFT]
                );

            if (lid_lip > 0)
                up(lid_t - eps)
                    right(porch_x0 + vm_wall_t + lid_fit_slop)
                        cuboid(
                            [lip_x, lip_y, lid_lip + eps],
                            anchor = LEFT + BOTTOM
                        );
        }

        tag("remove") {
            for (p = post_coords)
                translate([p.x, p.y, -eps / 2])
                    screw_hole(
                        lid_screw,
                        l = lid_t + lid_lip + eps,
                        teardrop = teardrop_holes,
                        anchor = BOTTOM,
                        orient = UP
                    );
        }
    }
}


motor_base_lid();
