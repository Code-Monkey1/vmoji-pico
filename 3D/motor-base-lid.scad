include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <BOSL2/gears.scad>
include <motor-base-common.scad>


/* [Deck / porch] */
// Must match motor-base.scad footprint math.
motor_d = 24; // [20:0.1:40]
collet_wall = 4.5; // [2:0.5:6]
collet_flange_od = 48; // [30:0.5:60]
gear_mod = 1.25; // [0.5:0.05:2]
pinion_teeth = 14; // [10:1:30]
driven_teeth = 28; // [16:1:60]
gear_helical = 25; // [0:1:40]
gear_backlash = 0.3; // [0:0.05:1]
ring_od = 41; // [20:0.1:100]
deck_margin = 4; // [2:0.5:10]
wall_t = 3; // [2:0.5:6]
porch_inner_x = 50; // [30:1:100]
porch_inner_y = 72; // [40:1:120]
lid_t = 2.5; // [1.5:0.5:5]
lid_lip = 0.8; // [0:0.1:2]
lid_fit_slop = 0.25; // [0.1:0.05:0.8]


/* [Posts] */
post_d = 8; // [6:0.5:14]
lid_screw = "M3";
teardrop_holes = true; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_base_lid(
    motor_d = motor_d,
    collet_wall = collet_wall,
    collet_flange_od = collet_flange_od,
    gear_mod = gear_mod,
    pinion_teeth = pinion_teeth,
    driven_teeth = driven_teeth,
    gear_helical = gear_helical,
    gear_backlash = gear_backlash,
    ring_od = ring_od,
    deck_margin = deck_margin,
    wall_t = wall_t,
    porch_inner_x = porch_inner_x,
    porch_inner_y = porch_inner_y,
    lid_t = lid_t,
    lid_lip = lid_lip,
    lid_fit_slop = lid_fit_slop,
    post_d = post_d,
    lid_screw = lid_screw,
    teardrop_holes = teardrop_holes
) {
    eps = cut_overlap;
    motor_y = mb_gear_center_dist(
        gear_mod, pinion_teeth, driven_teeth, gear_helical, gear_backlash
    );
    driven_od = mb_gear_outer_d(driven_teeth, gear_mod, gear_helical);
    pinion_od = mb_gear_outer_d(pinion_teeth, gear_mod, gear_helical);
    bearing_pocket_d = mb_bearing_pocket_d();

    layout = mb_layout(
        motor_y, motor_d, collet_flange_od, driven_od, pinion_od,
        ring_od, bearing_pocket_d, deck_margin, wall_t
    );
    deck_half_x = mb_layout_get(layout, "deck_half_x");
    deck_half_y = mb_layout_get(layout, "deck_half_y");

    porch_x0 = deck_half_x - wall_t;
    porch_outer_x = porch_inner_x + 2 * wall_t;
    porch_outer_y = porch_inner_y + 2 * wall_t;
    porch_x1 = porch_x0 + porch_outer_x;

    post_inset = wall_t + post_d / 2 + 1;
    post_coords = [
        [porch_x0 + post_inset,  porch_inner_y / 2 - post_d / 2 - 1],
        [porch_x0 + post_inset, -(porch_inner_y / 2 - post_d / 2 - 1)],
        [porch_x1 - post_inset,  porch_inner_y / 2 - post_d / 2 - 1],
        [porch_x1 - post_inset, -(porch_inner_y / 2 - post_d / 2 - 1)]
    ];

    lip_x = porch_inner_x - 2 * lid_fit_slop;
    lip_y = porch_inner_y - 2 * lid_fit_slop;

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
                    right(porch_x0 + wall_t + lid_fit_slop)
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
