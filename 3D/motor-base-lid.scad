include <BOSL2/std.scad>
include <BOSL2/screws.scad>
include <motor-base-common.scad>


/* [Porch] */
// Must match motor-base.scad outer porch footprint.
deck_od = 60; // [45:0.5:90]
wall_t = 2.5; // [1.5:0.5:5]
porch_inner_x = 50; // [30:1:100]
porch_inner_y = 72; // [40:1:120]
lid_t = 2.5; // [1.5:0.5:5]
lid_lip = 0.8; // [0:0.1:2]
lid_fit_slop = 0.25; // [0.1:0.05:0.8]


/* [Posts] */
// Must match motor-base.scad post layout.
post_d = 8; // [6:0.5:14]
lid_screw = "M3";
teardrop_holes = true; // [true, false]


/* [Hidden] */
$fa = 2;
$fs = 0.25;
$slop = 0.2;
cut_overlap = 0.2;


module motor_base_lid(
    deck_od = deck_od,
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
    porch_x0 = deck_od / 2 - wall_t;
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

    hole_d = mb_clearance_hole_d(lid_screw);
    // Inset lip that drops into the porch opening.
    lip_x = porch_inner_x - 2 * lid_fit_slop;
    lip_y = porch_inner_y - 2 * lid_fit_slop;

    diff() {
        union() {
            // Top plate covers the porch outer footprint.
            right(porch_x0)
                cuboid(
                    [porch_outer_x, porch_outer_y, lid_t],
                    anchor = LEFT + BOTTOM,
                    chamfer = 1,
                    edges = [FRONT + RIGHT, BACK + RIGHT, FRONT + LEFT, BACK + LEFT]
                );

            // Locating lip into the porch cavity (sink into plate so it unions).
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
